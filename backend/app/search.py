"""Hybrid note search: semantic (vectors) + keyword (Atlas Search), merged with Reciprocal Rank Fusion.

On Atlas M0 `$rankFusion` isn't available, so we run both queries and fuse in Python.
If Atlas Search isn't available (local mongod, tests, index still building) we score in-process.
"""
from __future__ import annotations

import asyncio
import logging
import math
import re
from collections import Counter

from .ai import gemini
from .ai.schemas import AskAnswer
from .config import get_settings
from .db import DB, note_out

log = logging.getLogger(__name__)

CANDIDATES = 50
FALLBACK_SCAN_LIMIT = 5000
_TOKEN = re.compile(r"[a-z0-9]+")
_STOP = {
    "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "about", "my", "i", "me", "that", "this",
    "is", "was", "it", "with", "what", "did", "had", "have", "idea", "ideas", "thought", "thoughts",
}


def rrf_merge(ranked_lists: list[tuple[str, list[dict], float]], k: int) -> list[dict]:
    """ranked_lists: (source_name, docs_in_rank_order, weight). Returns docs with `_score` and `_match`."""
    scores: dict[str, float] = {}
    sources: dict[str, set[str]] = {}
    docs: dict[str, dict] = {}
    for source, ranked, weight in ranked_lists:
        for rank, doc in enumerate(ranked):
            key = str(doc["_id"])
            scores[key] = scores.get(key, 0.0) + weight / (k + rank + 1)
            sources.setdefault(key, set()).add(source)
            docs.setdefault(key, doc)
    out = []
    for key in sorted(scores, key=scores.get, reverse=True):
        doc = docs[key]
        src = sources[key]
        doc["_score"] = scores[key]
        doc["_match"] = "both" if len(src) > 1 else next(iter(src))
        out.append(doc)
    return out


# --------------------------------------------------------------------------- Atlas path


async def _atlas_vector(db, qvec: list[float], user_id: str) -> list[dict]:
    s = get_settings()
    cursor = await db.notes.aggregate(
        [
            {
                "$vectorSearch": {
                    "index": s.vector_index_name,
                    "path": "embedding",
                    "queryVector": qvec,
                    "numCandidates": CANDIDATES * 4,
                    "limit": CANDIDATES * 2,
                }
            },
            {"$addFields": {"_vs": {"$meta": "vectorSearchScore"}}},
            # Atlas normalizes cosine to (1 + cos) / 2
            {"$match": {"user_id": user_id, "_vs": {"$gte": (1 + s.semantic_min_score) / 2}}},
            {"$limit": CANDIDATES},
            {"$project": {"embedding": 0, "_vs": 0}},
        ]
    )
    return await cursor.to_list(length=None)


async def _atlas_text(db, q: str, user_id: str) -> list[dict]:
    s = get_settings()
    cursor = await db.notes.aggregate(
        [
            {
                "$search": {
                    "index": s.text_index_name,
                    "compound": {
                        "should": [
                            {"phrase": {"query": q, "path": ["text", "title"], "score": {"boost": {"value": 3}}}},
                            {"text": {"query": q, "path": ["text", "title", "tags"], "fuzzy": {"maxEdits": 1}}},
                        ]
                    },
                }
            },
            {"$match": {"user_id": user_id}},
            {"$limit": CANDIDATES},
            {"$project": {"embedding": 0}},
        ]
    )
    return await cursor.to_list(length=None)


# --------------------------------------------------------------------------- in-process fallback


def _tokens(s: str) -> list[str]:
    return [t for t in _TOKEN.findall(s.lower()) if t not in _STOP]


def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b, strict=False))
    na = math.sqrt(sum(x * x for x in a)) or 1.0
    nb = math.sqrt(sum(y * y for y in b)) or 1.0
    return dot / (na * nb)


def _is_exact_match(doc: dict, phrase: str) -> bool:
    if not phrase:
        return False
    haystack = f"{doc.get('title') or ''}\n{doc.get('text', '')}\n{' '.join(doc.get('tags', []))}".lower()
    return phrase in haystack


def _keyword_rank(q: str, docs: list[dict]) -> list[dict]:
    """Small BM25-ish scorer with an exact-phrase bonus."""
    q_tokens = _tokens(q)
    phrase = q.lower().strip()
    if not q_tokens and not phrase:
        return []
    n = len(docs) or 1
    df = Counter()
    doc_tokens = []
    for d in docs:
        toks = _tokens(f"{d.get('title') or ''} {d.get('text', '')} {' '.join(d.get('tags', []))}")
        doc_tokens.append(toks)
        df.update(set(toks))
    avg_len = sum(len(t) for t in doc_tokens) / n or 1.0
    scored = []
    for d, toks in zip(docs, doc_tokens, strict=True):
        tf = Counter(toks)
        score = 0.0
        for t in q_tokens:
            if tf[t]:
                idf = math.log(1 + (n - df[t] + 0.5) / (df[t] + 0.5))
                score += idf * tf[t] * 2.2 / (tf[t] + 1.2 * (0.25 + 0.75 * len(toks) / avg_len))
        if _is_exact_match(d, phrase):
            score += 5.0
        if score > 0:
            scored.append((score, d))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [d for _, d in scored[:CANDIDATES]]


async def _fallback_search(db, q: str, qvec: list[float] | None, user_id: str) -> tuple[list[dict], list[dict]]:
    docs = (
        await db.notes.find({"user_id": user_id})
        .sort("created_at", -1)
        .limit(FALLBACK_SCAN_LIMIT)
        .to_list(length=None)
    )
    vec_ranked: list[dict] = []
    if qvec is not None:
        with_vec = [(d, _cosine(qvec, d["embedding"])) for d in docs if d.get("embedding")]
        with_vec.sort(key=lambda x: x[1], reverse=True)
        # Drop clearly unrelated notes so semantic search doesn't return everything.
        min_score = get_settings().semantic_min_score
        vec_ranked = [d for d, s in with_vec[:CANDIDATES] if s >= min_score]
    return vec_ranked, _keyword_rank(q, docs)


# --------------------------------------------------------------------------- public API


async def _atlas_exact(db, q: str, limit: int, user_id: str) -> list[dict]:
    pattern = re.escape(q)
    cursor = (
        db.notes.find(
            {
                "user_id": user_id,
                "$or": [
                    {"title": {"$regex": pattern, "$options": "i"}},
                    {"text": {"$regex": pattern, "$options": "i"}},
                    {"tags": {"$regex": pattern, "$options": "i"}},
                ],
            },
            {"embedding": 0},
        )
        .sort("created_at", -1)
        .limit(limit)
    )
    return await cursor.to_list(length=None)


async def hybrid_search(db, q: str, limit: int = 15, user_id: str = "default") -> list[dict]:
    s = get_settings()
    q = q.strip()
    if not q:
        return []
    try:
        qvec: list[float] | None = await gemini.embed(q, "query")
    except Exception as exc:  # noqa: BLE001
        log.warning("Query embedding failed (%s); keyword-only search", exc)
        qvec = None

    vec_ranked: list[dict] = []
    txt_ranked: list[dict] = []
    if DB.atlas_search:
        try:
            tasks = [_atlas_exact(db, q, limit, user_id), _atlas_text(db, q, user_id)]
            if qvec is not None:
                tasks.insert(0, _atlas_vector(db, qvec, user_id))
            results = await asyncio.gather(*tasks)
            atlas_txt = results[-1]
            exact_docs = results[-2]
            seen_ids = {str(d["_id"]) for d in exact_docs}
            txt_ranked = exact_docs + [d for d in atlas_txt if str(d["_id"]) not in seen_ids]
            vec_ranked = results[0] if qvec is not None else []
        except Exception as exc:  # noqa: BLE001 - e.g. index still building
            log.warning("Atlas search failed (%s); using in-process fallback", exc)
            vec_ranked, txt_ranked = await _fallback_search(db, q, qvec, user_id)
    else:
        vec_ranked, txt_ranked = await _fallback_search(db, q, qvec, user_id)

    fused = rrf_merge(
        [("semantic", vec_ranked, s.semantic_weight), ("keyword", txt_ranked, s.keyword_weight)], k=s.rrf_k
    )
    phrase = q.lower()
    exact = [d for d in fused if _is_exact_match(d, phrase)]
    related = [d for d in fused if not _is_exact_match(d, phrase)]
    ordered = (exact + related)[:limit]
    return [
        {"note": note_out(d), "score": round(d["_score"], 5), "match": d["_match"]} for d in ordered
    ]


ASK_SYSTEM = """You answer questions about the user's own journal notes.
Use ONLY the numbered notes provided. Cite notes inline like [1] or [2][3].
If the notes don't contain the answer, say so briefly. Be concise and speak to the user as "you"."""


async def ask(db, question: str, k: int = 6, user_id: str = "default") -> dict:
    results = await hybrid_search(db, question, limit=k, user_id=user_id)
    notes = [r["note"] for r in results]
    if not notes:
        return {"answer": "I couldn't find any notes related to that yet.", "citations": []}
    context = "\n\n".join(
        f"[{i}] ({n['created_at'][:10]}) {n['title'] or ''}\n{n['text']}" for i, n in enumerate(notes, start=1)
    )
    try:
        out = await gemini.generate_json(
            ASK_SYSTEM, f"NOTES:\n{context}\n\nQUESTION: {question}", AskAnswer, temperature=0.2
        )
        answer = out.answer
    except Exception as exc:  # noqa: BLE001
        log.warning("Ask failed (%s)", exc)
        answer = "AI answers are unavailable right now — here are the most relevant notes."
    return {"answer": answer, "citations": notes}
