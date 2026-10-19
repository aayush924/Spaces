"""Notes, lists, list items and todos CRUD (see docs/API.md)."""
from datetime import date, datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field, field_validator

from ..auth import current_user_id
from ..db import get_db, list_item_out, note_out, now_utc, oid, todo_out
from ..services import create_list, create_note, embed_note, list_summary

router = APIRouter()


def _check_date(v: str | None) -> str | None:
    if v is None:
        return v
    try:
        return date.fromisoformat(v).isoformat()
    except ValueError as exc:
        raise ValueError("must be YYYY-MM-DD") from exc


# ============================================================================ notes


class NoteIn(BaseModel):
    text: str = Field(min_length=1)
    title: str | None = None
    tags: list[str] = []


class NotePatch(BaseModel):
    text: str | None = Field(default=None, min_length=1)
    title: str | None = None
    tags: list[str] | None = None


@router.get("/notes")
async def list_notes(
    limit: int = Query(50, ge=1, le=200),
    before: datetime | None = None,
    user_id: str = Depends(current_user_id),
    db=Depends(get_db),
):
    query: dict = {"user_id": user_id}
    if before:
        query["created_at"] = {"$lt": before}
    docs = await db.notes.find(query, {"embedding": 0}).sort("created_at", -1).limit(limit).to_list(length=None)
    return [note_out(d) for d in docs]


@router.post("/notes", status_code=201)
async def add_note(body: NoteIn, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    return note_out(await create_note(db, body.text, body.title, body.tags, user_id=user_id))


async def _get_note(db, note_id: str, user_id: str) -> dict:
    doc = await db.notes.find_one({"_id": oid(note_id), "user_id": user_id}, {"embedding": 0})
    if doc is None:
        raise HTTPException(404, "Note not found")
    return doc


@router.get("/notes/{note_id}")
async def get_note(note_id: str, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    return note_out(await _get_note(db, note_id, user_id))


@router.patch("/notes/{note_id}")
async def patch_note(note_id: str, body: NotePatch, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    doc = await _get_note(db, note_id, user_id)
    update: dict = {"updated_at": now_utc()}
    if body.title is not None:
        update["title"] = body.title.strip()
    if body.tags is not None:
        update["tags"] = [t.strip().lower() for t in body.tags if t.strip()]
    if body.text is not None:
        update["text"] = body.text.strip()
    if body.text is not None or body.title is not None:
        update["embedding"] = await embed_note(update.get("text", doc["text"]), update.get("title", doc.get("title")))
    await db.notes.update_one({"_id": doc["_id"]}, {"$set": update})
    return note_out(await _get_note(db, note_id, user_id))


@router.delete("/notes/{note_id}", status_code=204)
async def delete_note(note_id: str, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    res = await db.notes.delete_one({"_id": oid(note_id), "user_id": user_id})
    if res.deleted_count == 0:
        raise HTTPException(404, "Note not found")
    return Response(status_code=204)


# ============================================================================ lists


class ListIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    kind: Literal["shopping", "wishlist", "custom"] | None = None


class ItemIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    quantity: str | None = None


class ItemPatch(BaseModel):
    text: str | None = Field(default=None, min_length=1)
    quantity: str | None = None
    done: bool | None = None


async def _get_list(db, list_id: str, user_id: str) -> dict:
    doc = await db.lists.find_one({"_id": oid(list_id), "user_id": user_id})
    if doc is None:
        raise HTTPException(404, "List not found")
    return doc


@router.get("/lists")
async def get_lists(user_id: str = Depends(current_user_id), db=Depends(get_db)):
    docs = await db.lists.find({"user_id": user_id}).sort("created_at", 1).to_list(length=None)
    if not docs and user_id != "default":
        from ..db import seed_default_lists

        await seed_default_lists(db, user_id=user_id)
        docs = await db.lists.find({"user_id": user_id}).sort("created_at", 1).to_list(length=None)
    return [await list_summary(db, d) for d in docs]


@router.post("/lists", status_code=201)
async def add_list(body: ListIn, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    return await list_summary(db, await create_list(db, body.name, body.kind, user_id=user_id))


@router.delete("/lists/{list_id}", status_code=204)
async def delete_list(list_id: str, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    doc = await _get_list(db, list_id, user_id)
    await db.list_items.delete_many({"list_id": doc["_id"]})
    await db.lists.delete_one({"_id": doc["_id"]})
    return Response(status_code=204)


@router.get("/lists/{list_id}/items")
async def get_items(list_id: str, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    doc = await _get_list(db, list_id, user_id)
    items = await db.list_items.find({"list_id": doc["_id"]}).sort([("done", 1), ("created_at", 1)]).to_list(
        length=None
    )
    return [list_item_out(i) for i in items]


@router.post("/lists/{list_id}/items", status_code=201)
async def add_item(list_id: str, body: ItemIn, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    doc = await _get_list(db, list_id, user_id)
    item = {
        "user_id": user_id,
        "list_id": doc["_id"],
        "text": body.text.strip(),
        "quantity": body.quantity,
        "done": False,
        "created_at": now_utc(),
        "capture_id": None,
    }
    res = await db.list_items.insert_one(item)
    item["_id"] = res.inserted_id
    return list_item_out(item)


@router.patch("/lists/{list_id}/items/{item_id}")
async def patch_item(
    list_id: str, item_id: str, body: ItemPatch, user_id: str = Depends(current_user_id), db=Depends(get_db)
):
    doc = await _get_list(db, list_id, user_id)
    update = body.model_dump(exclude_unset=True)
    if update:
        await db.list_items.update_one({"_id": oid(item_id), "list_id": doc["_id"]}, {"$set": update})
    item = await db.list_items.find_one({"_id": oid(item_id), "list_id": doc["_id"]})
    if item is None:
        raise HTTPException(404, "Item not found")
    return list_item_out(item)


@router.delete("/lists/{list_id}/items/{item_id}", status_code=204)
async def delete_item(list_id: str, item_id: str, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    doc = await _get_list(db, list_id, user_id)
    res = await db.list_items.delete_one({"_id": oid(item_id), "list_id": doc["_id"]})
    if res.deleted_count == 0:
        raise HTTPException(404, "Item not found")
    return Response(status_code=204)


@router.delete("/lists/{list_id}/items")
async def clear_items(list_id: str, done: bool = True, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    doc = await _get_list(db, list_id, user_id)
    res = await db.list_items.delete_many({"list_id": doc["_id"], "done": done})
    return {"deleted": res.deleted_count}


# ============================================================================ todos


class TodoIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    due_date: str

    _v = field_validator("due_date")(_check_date)


class TodoPatch(BaseModel):
    text: str | None = Field(default=None, min_length=1)
    due_date: str | None = None
    done: bool | None = None

    _v = field_validator("due_date")(_check_date)


@router.get("/todos")
async def get_todos(
    date_: str | None = Query(None, alias="date"),
    overdue_before: str | None = None,
    user_id: str = Depends(current_user_id),
    db=Depends(get_db),
):
    try:
        if date_:
            query: dict = {"user_id": user_id, "due_date": _check_date(date_)}
        elif overdue_before:
            query = {"user_id": user_id, "due_date": {"$lt": _check_date(overdue_before)}, "done": False}
        else:
            raise HTTPException(422, "Provide ?date=YYYY-MM-DD or ?overdue_before=YYYY-MM-DD")
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    docs = await db.todos.find(query).sort([("due_date", 1), ("done", 1), ("created_at", 1)]).to_list(length=None)
    return [todo_out(d) for d in docs]


@router.post("/todos", status_code=201)
async def add_todo(body: TodoIn, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    doc = {
        "user_id": user_id,
        "text": body.text.strip(),
        "due_date": body.due_date,
        "done": False,
        "done_at": None,
        "created_at": now_utc(),
        "capture_id": None,
    }
    res = await db.todos.insert_one(doc)
    doc["_id"] = res.inserted_id
    return todo_out(doc)


@router.patch("/todos/{todo_id}")
async def patch_todo(todo_id: str, body: TodoPatch, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    update = body.model_dump(exclude_unset=True)
    if "done" in update:
        update["done_at"] = now_utc() if update["done"] else None
    if update:
        await db.todos.update_one({"_id": oid(todo_id), "user_id": user_id}, {"$set": update})
    doc = await db.todos.find_one({"_id": oid(todo_id), "user_id": user_id})
    if doc is None:
        raise HTTPException(404, "Todo not found")
    return todo_out(doc)


@router.delete("/todos/{todo_id}", status_code=204)
async def delete_todo(todo_id: str, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    res = await db.todos.delete_one({"_id": oid(todo_id), "user_id": user_id})
    if res.deleted_count == 0:
        raise HTTPException(404, "Todo not found")
    return Response(status_code=204)
