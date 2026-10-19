"""Test fixtures: an async adapter over mongomock + a fake Gemini. No network needed."""
from __future__ import annotations

import hashlib
import math
import os
import re

import mongomock
import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("API_TOKEN", "test-token")
os.environ.setdefault("GEMINI_API_KEY", "")
os.environ.setdefault("BOOTSTRAP_SEARCH_INDEXES", "false")

from app import db as dbmod  # noqa: E402
from app.ai import gemini  # noqa: E402
from app.ai.gemini import AIUnavailable  # noqa: E402
from app.ai.schemas import AskAnswer, RouterResult  # noqa: E402
from app.config import get_settings  # noqa: E402

# --------------------------------------------------------------------------- async mongomock adapter


class AsyncCursor:
    def __init__(self, cursor):
        self._c = cursor

    def sort(self, key, direction=None):
        self._c = self._c.sort(key, direction) if direction is not None else self._c.sort(key)
        return self

    def limit(self, n):
        self._c = self._c.limit(n)
        return self

    async def to_list(self, length=None):
        return list(self._c)

    def __aiter__(self):
        self._it = iter(self._c)
        return self

    async def __anext__(self):
        try:
            return next(self._it)
        except StopIteration as exc:
            raise StopAsyncIteration from exc


class AsyncCollection:
    def __init__(self, coll):
        self._c = coll

    def find(self, *args, **kwargs):
        return AsyncCursor(self._c.find(*args, **kwargs))

    async def aggregate(self, pipeline):
        return AsyncCursor(self._c.aggregate(pipeline))

    async def list_search_indexes(self):
        raise RuntimeError("search indexes not supported in mongomock")

    def __getattr__(self, name):
        attr = getattr(self._c, name)
        if callable(attr):
            async def wrapper(*a, **kw):
                return attr(*a, **kw)
            return wrapper
        return attr


class AsyncDatabase:
    def __init__(self, database):
        self._db = database

    def __getattr__(self, name):
        return AsyncCollection(self._db[name])

    def __getitem__(self, name):
        return AsyncCollection(self._db[name])

    async def list_collection_names(self):
        return self._db.list_collection_names()

    async def create_collection(self, name):
        return self._db.create_collection(name)


# --------------------------------------------------------------------------- fake Gemini

# Tiny "concept" map so the fake embedding behaves semantically for tests.
CONCEPTS = {
    "bike": "bicycle", "bikes": "bicycle", "bicycles": "bicycle", "bicycle": "bicycle", "cycling": "bicycle",
    "garage": "garage", "pegboard": "storage", "storing": "storage", "storage": "storage", "hang": "storage",
    "store": "storage", "plant": "plant", "plants": "plant", "watering": "plant", "garden": "plant",
    "app": "software", "software": "software", "startup": "software",
}


FAKE_STOP = {
    "task", "search", "result", "query", "title", "text", "none",
    "what", "if", "the", "a", "an", "had", "so", "to", "that", "of", "and", "i", "did", "think", "about",
}


def fake_vector(text: str, dim: int = 768) -> list[float]:
    vec = [0.0] * dim
    for tok in re.findall(r"[a-z]+", text.lower()):
        if tok in FAKE_STOP:
            continue
        key = CONCEPTS.get(tok, tok)
        h = int(hashlib.md5(key.encode()).hexdigest(), 16)
        vec[h % dim] += 1.0
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


class FakeGemini:
    def __init__(self):
        self.router_results: dict[str, RouterResult] = {}
        self.ask_answer = "You had an idea about garage bike storage [1]."
        self.embed_fails = False
        self.calls: list[str] = []

    async def generate_json(self, system, prompt, schema, temperature=0.0):
        self.calls.append(prompt)
        if schema is RouterResult:
            text = prompt.rsplit("Input: ", 1)[-1].removesuffix("\nOutput:")
            if text in self.router_results:
                return self.router_results[text]
            raise AIUnavailable("no scripted router result (forces rule fallback)")
        if schema is AskAnswer:
            return AskAnswer(answer=self.ask_answer)
        raise AIUnavailable("unexpected schema")

    async def embed(self, text, kind, title=None):
        if self.embed_fails:
            raise AIUnavailable("embedding disabled")
        return fake_vector(f"{title or ''} {text}")


@pytest.fixture
def fake_ai(monkeypatch):
    fake = FakeGemini()
    monkeypatch.setattr(gemini, "generate_json", fake.generate_json)
    monkeypatch.setattr(gemini, "embed", fake.embed)
    return fake


@pytest.fixture
def mdb():
    database = AsyncDatabase(mongomock.MongoClient(tz_aware=True)["myspaces_test"])
    dbmod.DB.db = database
    dbmod.DB.atlas_search = False
    yield database
    dbmod.DB.db = None


@pytest.fixture
def client(mdb, fake_ai):
    import asyncio

    from app.main import app

    get_settings.cache_clear()
    asyncio.run(dbmod.ensure_indexes(mdb))
    asyncio.run(dbmod.seed_default_lists(mdb))
    with TestClient(app, headers={"Authorization": "Bearer test-token"}) as c:
        yield c
