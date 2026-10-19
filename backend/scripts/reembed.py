"""Backfill embeddings for notes saved while Gemini was unavailable. Usage: make reembed"""
import asyncio

from app import db as dbmod
from app.config import get_settings
from app.services import embed_note


async def main() -> None:
    settings = get_settings()
    settings.bootstrap_search_indexes = False
    await dbmod.connect(settings)
    db = dbmod.DB.db
    fixed = 0
    async for doc in db.notes.find({"$or": [{"embedding": None}, {"embedding": {"$exists": False}}]}):
        vec = await embed_note(doc["text"], doc.get("title"))
        if vec:
            await db.notes.update_one({"_id": doc["_id"]}, {"$set": {"embedding": vec}})
            fixed += 1
    print(f"Re-embedded {fixed} notes")
    await dbmod.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
