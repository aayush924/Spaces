"""MongoDB connection, index bootstrap and document serializers."""
from __future__ import annotations

import logging
from datetime import UTC, datetime
from typing import Any

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import HTTPException
from pymongo import ASCENDING, DESCENDING, AsyncMongoClient
from pymongo.operations import SearchIndexModel

from .config import Settings

log = logging.getLogger(__name__)

DEFAULT_LISTS = [
    {"name": "Costco", "kind": "shopping", "aliases": ["costco list"]},
    {"name": "Walmart", "kind": "shopping", "aliases": ["walmart list"]},
    {"name": "Wish List", "kind": "wishlist", "aliases": ["wishlist", "wish list", "wants"]},
]


class DB:
    """Holds the active database handle. Tests replace `DB.db` with a fake."""

    client: AsyncMongoClient | None = None
    db: Any = None
    # Whether Atlas Search / Vector Search are usable (false on plain mongod / tests)
    atlas_search: bool = False


def get_db():
    return DB.db


async def connect(settings: Settings) -> None:
    DB.client = AsyncMongoClient(settings.mongodb_uri, tz_aware=True, appname="myspaces")
    DB.db = DB.client[settings.mongodb_db]
    await DB.client.admin.command("ping")
    await ensure_indexes(DB.db)
    await seed_default_lists(DB.db)
    if settings.bootstrap_search_indexes:
        DB.atlas_search = await ensure_search_indexes(DB.db, settings)


async def disconnect() -> None:
    if DB.client is not None:
        await DB.client.close()
        DB.client = None


async def ensure_indexes(db) -> None:
    try:
        await db.lists.drop_index("slug_1")
    except Exception:  # noqa: BLE001
        pass
    await db.notes.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.notes.create_index([("capture_id", ASCENDING)])
    await db.lists.create_index([("user_id", ASCENDING), ("slug", ASCENDING)], unique=True)
    await db.list_items.create_index([("list_id", ASCENDING), ("done", ASCENDING), ("created_at", ASCENDING)])
    await db.list_items.create_index([("capture_id", ASCENDING)])
    await db.todos.create_index([("user_id", ASCENDING), ("due_date", ASCENDING), ("done", ASCENDING)])
    await db.todos.create_index([("capture_id", ASCENDING)])
    await db.captures.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.users.create_index([("email", ASCENDING)], unique=True)
    await db.users.create_index([("token", ASCENDING)])


def vector_index_definition(settings: Settings) -> dict:
    return {
        "fields": [
            {
                "type": "vector",
                "path": "embedding",
                "numDimensions": settings.embed_dim,
                "similarity": "cosine",
            }
        ]
    }


TEXT_INDEX_DEFINITION = {
    "mappings": {
        "dynamic": False,
        "fields": {
            "text": {"type": "string"},
            "title": {"type": "string"},
            "tags": {"type": "string"},
        },
    }
}


async def ensure_search_indexes(db, settings: Settings) -> bool:
    """Create Atlas Vector Search + Atlas Search indexes if missing.

    Returns False when the deployment doesn't support search indexes (e.g. local mongod);
    search then falls back to in-process scoring.
    """
    try:
        cursor = await db.notes.list_search_indexes()
        existing = {ix["name"] for ix in await cursor.to_list(length=None)}
    except Exception as exc:  # noqa: BLE001 - any failure means "no Atlas Search here"
        log.warning("Atlas Search unavailable (%s); using in-process search fallback", exc)
        return False

    # Collection must exist before search indexes can be created on it.
    if "notes" not in await db.list_collection_names():
        await db.create_collection("notes")

    models = []
    if settings.vector_index_name not in existing:
        models.append(
            SearchIndexModel(
                definition=vector_index_definition(settings),
                name=settings.vector_index_name,
                type="vectorSearch",
            )
        )
    if settings.text_index_name not in existing:
        models.append(
            SearchIndexModel(definition=TEXT_INDEX_DEFINITION, name=settings.text_index_name, type="search")
        )
    if models:
        try:
            await db.notes.create_search_indexes(models)
            log.info("Requested creation of search indexes: %s", [m.document["name"] for m in models])
        except Exception as exc:  # noqa: BLE001
            log.warning("Could not create search indexes (%s); using fallback search", exc)
            return False
    return True


async def seed_default_lists(db, user_id: str = "default") -> None:
    for spec in DEFAULT_LISTS:
        slug = slugify(spec["name"])
        if await db.lists.find_one({"user_id": user_id, "slug": slug}) is None:
            await db.lists.insert_one({**spec, "user_id": user_id, "slug": slug, "created_at": now_utc()})


# --------------------------------------------------------------------------- helpers


def now_utc() -> datetime:
    return datetime.now(UTC)


def slugify(name: str) -> str:
    out = "".join(c.lower() if c.isalnum() else "-" for c in name.strip())
    while "--" in out:
        out = out.replace("--", "-")
    return out.strip("-") or "list"


def oid(value: str) -> ObjectId:
    try:
        return ObjectId(value)
    except (InvalidId, TypeError) as exc:
        raise HTTPException(status_code=404, detail="Not found") from exc


def iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def note_out(doc: dict) -> dict:
    return {
        "id": str(doc["_id"]),
        "text": doc.get("text", ""),
        "title": doc.get("title"),
        "tags": doc.get("tags", []),
        "created_at": iso(doc.get("created_at")),
        "updated_at": iso(doc.get("updated_at") or doc.get("created_at")),
    }


def list_item_out(doc: dict) -> dict:
    return {
        "id": str(doc["_id"]),
        "list_id": str(doc["list_id"]),
        "text": doc["text"],
        "quantity": doc.get("quantity"),
        "done": bool(doc.get("done", False)),
        "created_at": iso(doc.get("created_at")),
    }


def todo_out(doc: dict) -> dict:
    return {
        "id": str(doc["_id"]),
        "text": doc["text"],
        "due_date": doc["due_date"],
        "done": bool(doc.get("done", False)),
        "done_at": iso(doc.get("done_at")),
        "created_at": iso(doc.get("created_at")),
    }


def capture_out(doc: dict) -> dict:
    return {
        "id": str(doc["_id"]),
        "raw_text": doc["raw_text"],
        "summary": doc.get("summary", ""),
        "actions": doc.get("actions", []),
        "suggestions": doc.get("suggestions", []),
        "undone": bool(doc.get("undone", False)),
        "created_at": iso(doc.get("created_at")),
    }
