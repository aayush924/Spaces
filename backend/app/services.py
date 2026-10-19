"""Domain helpers shared by the executor and the REST routes."""
from __future__ import annotations

import difflib
import logging
import re

from bson import ObjectId

from .ai import gemini
from .db import now_utc, slugify

log = logging.getLogger(__name__)


# --------------------------------------------------------------------------- lists


def _norm_list_name(name: str) -> str:
    n = name.lower().strip()
    n = re.sub(r"^(my|the)\s+", "", n)
    n = re.sub(r"[’']s\b", "", n)
    n = re.sub(r"\s*(shopping\s+)?list$", "", n)
    return n.replace(" ", "").replace("-", "")


async def find_list(db, name: str, user_id: str = "default") -> dict | None:
    """Fuzzy-match a spoken list name against existing lists (name, slug, aliases) for this user."""
    target = _norm_list_name(name)
    if not target:
        return None
    best, best_score = None, 0.0
    async for doc in db.lists.find({"user_id": user_id}):
        candidates = [doc["name"], doc["slug"], *doc.get("aliases", [])]
        for c in candidates:
            score = difflib.SequenceMatcher(None, target, _norm_list_name(c)).ratio()
            if score > best_score:
                best, best_score = doc, score
    return best if best_score >= 0.82 else None


async def create_list(db, name: str, kind: str | None = None, user_id: str = "default") -> dict:
    name = name.strip()
    name = re.sub(r"\s*list$", "", name, flags=re.IGNORECASE).strip() or name
    name = name if any(c.isupper() for c in name) else name.title()
    if kind not in ("shopping", "wishlist", "custom"):
        kind = "wishlist" if "wish" in name.lower() else "custom"
    slug = slugify(name)
    existing = await db.lists.find_one({"user_id": user_id, "slug": slug})
    if existing:
        return existing
    doc = {"user_id": user_id, "name": name, "slug": slug, "kind": kind, "aliases": [], "created_at": now_utc()}
    res = await db.lists.insert_one(doc)
    doc["_id"] = res.inserted_id
    return doc


async def resolve_list(db, name: str, kind: str | None = None, user_id: str = "default") -> tuple[dict, bool]:
    """Returns (list_doc, created)."""
    found = await find_list(db, name, user_id=user_id)
    if found:
        return found, False
    return await create_list(db, name, kind, user_id=user_id), True


async def list_summary(db, doc: dict) -> dict:
    from .db import iso

    total = await db.list_items.count_documents({"list_id": doc["_id"]})
    open_ = await db.list_items.count_documents({"list_id": doc["_id"], "done": False})
    return {
        "id": str(doc["_id"]),
        "name": doc["name"],
        "slug": doc["slug"],
        "kind": doc.get("kind", "custom"),
        "item_count": total,
        "open_count": open_,
        "created_at": iso(doc.get("created_at")),
    }


# --------------------------------------------------------------------------- notes


def derive_title(text: str) -> str:
    words = text.strip().split()
    title = " ".join(words[:6])
    return title + ("…" if len(words) > 6 else "")


async def embed_note(text: str, title: str | None) -> list[float] | None:
    try:
        return await gemini.embed(text, "document", title=title)
    except Exception as exc:  # noqa: BLE001 - note is still saved; `make reembed` can backfill
        log.warning("Embedding failed, saving note without vector: %s", exc)
        return None


async def create_note(
    db,
    text: str,
    title: str | None = None,
    tags: list[str] | None = None,
    capture_id: ObjectId | None = None,
    user_id: str = "default",
) -> dict:
    title = (title or "").strip() or derive_title(text)
    now = now_utc()
    doc = {
        "user_id": user_id,
        "text": text.strip(),
        "title": title,
        "tags": tags or [],
        "embedding": await embed_note(text, title),
        "created_at": now,
        "updated_at": now,
        "capture_id": capture_id,
    }
    res = await db.notes.insert_one(doc)
    doc["_id"] = res.inserted_id
    return doc


# --------------------------------------------------------------------------- fuzzy text matching


def text_match_score(a: str, b: str) -> float:
    a, b = a.lower().strip(), b.lower().strip()
    if not a or not b:
        return 0.0
    if a in b or b in a:
        return 0.95
    ta, tb = set(re.findall(r"\w+", a)), set(re.findall(r"\w+", b))
    jacc = len(ta & tb) / max(1, len(ta | tb))
    return max(jacc, difflib.SequenceMatcher(None, a, b).ratio())
