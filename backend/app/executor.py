"""Executes routed actions against MongoDB, records captures, and supports undo."""
from __future__ import annotations

from datetime import date, datetime, timedelta

from bson import ObjectId
from fastapi import HTTPException

from .ai.router import RouteContext, route
from .ai.schemas import RoutedAction
from .config import get_settings
from .db import capture_out, now_utc, oid
from .services import create_note, find_list, resolve_list, text_match_score


def _empty_effects() -> dict:
    return {
        "notes": [],
        "list_items": [],
        "lists_created": [],
        "todos": [],
        "todos_completed": [],
        "list_items_deleted": [],
    }


def _day_label(due: str, today: date) -> str:
    d = date.fromisoformat(due)
    delta = (d - today).days
    if delta == 0:
        return "Today"
    if delta == 1:
        return "Tomorrow"
    if delta == -1:
        return "Yesterday"
    return d.strftime("%a %b ") + str(d.day)


def _plural(n: int, word: str) -> str:
    return f"{n} {word}{'' if n == 1 else 's'}"


def _executed(a: RoutedAction, summary: str, **kw) -> dict:
    return {
        "type": a.type,
        "summary": summary,
        "confidence": round(a.confidence, 2),
        "note_id": kw.get("note_id"),
        "list_id": kw.get("list_id"),
        "list_name": kw.get("list_name"),
        "due_date": kw.get("due_date"),
        "items": kw.get("items", []),
    }


class Executor:
    def __init__(self, db, ctx: RouteContext, capture_id: ObjectId, user_id: str = "default"):
        self.db = db
        self.ctx = ctx
        self.capture_id = capture_id
        self.user_id = user_id
        self.effects = _empty_effects()

    async def note(self, a: RoutedAction) -> dict:
        doc = await create_note(self.db, a.note_text or "", a.title, a.tags, self.capture_id, user_id=self.user_id)
        self.effects["notes"].append(doc["_id"])
        return _executed(a, f"Note saved: {doc['title']}", note_id=str(doc["_id"]))

    async def list_add(self, a: RoutedAction, list_name: str | None = None, items: list[str] | None = None) -> dict:
        name = list_name or a.list_name or "Wish List"
        lst, created = await resolve_list(self.db, name, a.list_kind, user_id=self.user_id)
        if created:
            self.effects["lists_created"].append(lst["_id"])
        existing = {
            d["text"].lower()
            async for d in self.db.list_items.find({"list_id": lst["_id"], "done": False}, {"text": 1})
        }
        added, skipped = [], []
        for text in items if items is not None else a.items:
            if text.lower() in existing:
                skipped.append(text)
                continue
            res = await self.db.list_items.insert_one(
                {
                    "user_id": self.user_id,
                    "list_id": lst["_id"],
                    "text": text,
                    "quantity": None,
                    "done": False,
                    "created_at": now_utc(),
                    "capture_id": self.capture_id,
                }
            )
            self.effects["list_items"].append(res.inserted_id)
            existing.add(text.lower())
            added.append(text)
        if added:
            summary = f"{_plural(len(added), 'item')} → {lst['name']}" + (" (new list)" if created else "")
        else:
            summary = f"Already on {lst['name']}: {', '.join(skipped)}"
        return _executed(a, summary, list_id=str(lst["_id"]), list_name=lst["name"], items=added)

    async def list_item_remove(self, a: RoutedAction) -> dict:
        lst = await find_list(self.db, a.list_name, user_id=self.user_id) if a.list_name else None
        if lst:
            query: dict = {"list_id": lst["_id"], "done": False}
        else:
            user_list_ids = [d["_id"] async for d in self.db.lists.find({"user_id": self.user_id}, {"_id": 1})]
            query = {"list_id": {"$in": user_list_ids}, "done": False}
        candidates = await self.db.list_items.find(query).to_list(length=None)
        removed = []
        for text in a.items:
            best = max(candidates, key=lambda d: text_match_score(text, d["text"]), default=None)
            if best is not None and text_match_score(text, best["text"]) >= 0.6:
                await self.db.list_items.delete_one({"_id": best["_id"]})
                self.effects["list_items_deleted"].append(best)
                candidates.remove(best)
                removed.append(best["text"])
        where = lst["name"] if lst else "your lists"
        summary = f"Removed {_plural(len(removed), 'item')} from {where}" if removed else f"Nothing matched on {where}"
        return _executed(
            a, summary, list_id=str(lst["_id"]) if lst else None, list_name=lst["name"] if lst else None, items=removed
        )

    async def todo_add(self, a: RoutedAction) -> dict:
        due = a.due_date or self.ctx.today.isoformat()
        for text in a.items:
            res = await self.db.todos.insert_one(
                {
                    "user_id": self.user_id,
                    "text": text,
                    "due_date": due,
                    "done": False,
                    "done_at": None,
                    "created_at": now_utc(),
                    "capture_id": self.capture_id,
                }
            )
            self.effects["todos"].append(res.inserted_id)
        summary = f"{_plural(len(a.items), 'todo')} for {_day_label(due, self.ctx.today)}"
        return _executed(a, summary, due_date=due, items=a.items)

    async def todo_complete(self, a: RoutedAction) -> dict:
        query: dict = {"user_id": self.user_id, "done": False}
        if a.due_date:
            query["due_date"] = a.due_date
        else:
            lo = (self.ctx.today - timedelta(days=14)).isoformat()
            hi = (self.ctx.today + timedelta(days=1)).isoformat()
            query["due_date"] = {"$gte": lo, "$lte": hi}
        candidates = await self.db.todos.find(query).to_list(length=None)
        done = []
        for text in a.items:
            best = max(candidates, key=lambda d: text_match_score(text, d["text"]), default=None)
            if best is not None and text_match_score(text, best["text"]) >= 0.55:
                await self.db.todos.update_one({"_id": best["_id"]}, {"$set": {"done": True, "done_at": now_utc()}})
                self.effects["todos_completed"].append(best["_id"])
                candidates.remove(best)
                done.append(best["text"])
        summary = f"Completed {_plural(len(done), 'todo')}" if done else "No matching open todo found"
        return _executed(a, summary, due_date=a.due_date, items=done)


def _overall_summary(actions: list[dict]) -> str:
    return " · ".join(f"✓ {a['summary']}" for a in actions)


async def run_capture(
    db, text: str, timezone: str | None, client_now: datetime | None, user_id: str = "default"
) -> dict:
    settings = get_settings()
    text = text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="text must not be empty")

    list_names = [d["name"] async for d in db.lists.find({"user_id": user_id}, {"name": 1})]
    ctx = RouteContext.build(timezone, client_now, list_names)
    routed, used_ai = await route(text, ctx)

    capture_id = ObjectId()
    ex = Executor(db, ctx, capture_id, user_id=user_id)
    executed: list[dict] = []
    suggestions: list[dict] = []
    fallback_note_id = None

    for a in routed:
        if a.type == "list_add" and a.confidence < settings.low_confidence_threshold:
            # Not sure enough: keep the raw thought as a note and offer a one-tap fix.
            if fallback_note_id is None and not any(r.type == "note" for r in routed):
                note_action = RoutedAction(type="note", note_text=text, confidence=a.confidence)
                res = await ex.note(note_action)
                executed.append(res)
                fallback_note_id = ObjectId(res["note_id"])
            target = a.list_name or "Wish List"
            item_str = ", ".join(f"“{i}”" for i in a.items)
            suggestions.append({"label": f"Add {item_str} to {target}", "list_name": target, "items": a.items})
            continue
        handler = getattr(ex, a.type)
        executed.append(await handler(a))

    summary = _overall_summary(executed)
    doc = {
        "_id": capture_id,
        "user_id": user_id,
        "raw_text": text,
        "timezone": timezone,
        "today": ctx.today.isoformat(),
        "used_ai": used_ai,
        "actions": executed,
        "suggestions": suggestions,
        "summary": summary,
        "effects": ex.effects,
        "fallback_note_id": fallback_note_id,
        "undone": False,
        "created_at": now_utc(),
    }
    await db.captures.insert_one(doc)
    return {"capture_id": str(capture_id), "summary": summary, "actions": executed, "suggestions": suggestions}


async def undo_capture(db, capture_id: str, user_id: str = "default") -> None:
    cap = await db.captures.find_one({"_id": oid(capture_id), "user_id": user_id})
    if cap is None:
        raise HTTPException(status_code=404, detail="Capture not found")
    if cap.get("undone"):
        return
    eff = cap.get("effects") or _empty_effects()
    if eff["notes"]:
        await db.notes.delete_many({"_id": {"$in": eff["notes"]}})
    if eff["list_items"]:
        await db.list_items.delete_many({"_id": {"$in": eff["list_items"]}})
    if eff["todos"]:
        await db.todos.delete_many({"_id": {"$in": eff["todos"]}})
    if eff["todos_completed"]:
        await db.todos.update_many(
            {"_id": {"$in": eff["todos_completed"]}}, {"$set": {"done": False, "done_at": None}}
        )
    for snapshot in eff["list_items_deleted"]:
        await db.list_items.replace_one({"_id": snapshot["_id"]}, snapshot, upsert=True)
    for list_id in eff["lists_created"]:
        if await db.list_items.count_documents({"list_id": list_id}) == 0:
            await db.lists.delete_one({"_id": list_id})
    await db.captures.update_one({"_id": cap["_id"]}, {"$set": {"undone": True}})


async def accept_suggestion(db, capture_id: str, index: int, user_id: str = "default") -> dict:
    cap = await db.captures.find_one({"_id": oid(capture_id), "user_id": user_id})
    if cap is None:
        raise HTTPException(status_code=404, detail="Capture not found")
    suggestions = cap.get("suggestions", [])
    if not 0 <= index < len(suggestions):
        raise HTTPException(status_code=404, detail="Suggestion not found")
    sug = suggestions.pop(index)

    ctx = RouteContext(today=date.fromisoformat(cap.get("today") or date.today().isoformat()), list_names=[])
    ex = Executor(db, ctx, cap["_id"], user_id=user_id)
    ex.effects = cap.get("effects") or _empty_effects()
    action = RoutedAction(type="list_add", list_name=sug["list_name"], items=sug["items"], confidence=1.0)
    executed = await ex.list_add(action)
    actions = cap.get("actions", [])

    # Once every suggestion is resolved the fallback note is redundant: remove it.
    fallback = cap.get("fallback_note_id")
    if fallback is not None and not suggestions:
        await db.notes.delete_one({"_id": fallback})
        ex.effects["notes"] = [n for n in ex.effects["notes"] if n != fallback]
        actions = [a for a in actions if a.get("note_id") != str(fallback)]
        fallback = None
    actions.append(executed)
    summary = _overall_summary(actions)
    await db.captures.update_one(
        {"_id": cap["_id"]},
        {
            "$set": {
                "actions": actions,
                "suggestions": suggestions,
                "summary": summary,
                "effects": ex.effects,
                "fallback_note_id": fallback,
            }
        },
    )
    return {"capture_id": str(cap["_id"]), "summary": summary, "actions": actions, "suggestions": suggestions}


async def list_captures(db, limit: int, user_id: str = "default") -> list[dict]:
    docs = await db.captures.find({"user_id": user_id}).sort("created_at", -1).limit(limit).to_list(length=None)
    return [capture_out(d) for d in docs]
