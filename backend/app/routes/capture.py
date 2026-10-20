"""Capture, search and ask endpoints."""
from datetime import datetime

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from .. import executor, search
from ..auth import current_user_id
from ..db import get_db

router = APIRouter()


class CaptureIn(BaseModel):
    text: str = Field(min_length=1, max_length=10_000)
    timezone: str | None = None
    client_now: datetime | None = None


class AskIn(BaseModel):
    question: str = Field(min_length=1, max_length=2_000)


@router.post("/capture")
async def capture(body: CaptureIn, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    return await executor.run_capture(db, body.text, body.timezone, body.client_now, user_id=user_id)


@router.get("/captures")
async def captures(
    limit: int = Query(20, ge=1, le=200), user_id: str = Depends(current_user_id), db=Depends(get_db)
):
    return await executor.list_captures(db, limit, user_id=user_id)


@router.post("/capture/{capture_id}/undo")
async def undo(capture_id: str, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    await executor.undo_capture(db, capture_id, user_id=user_id)
    return {"undone": True}


@router.post("/capture/{capture_id}/suggestions/{index}/accept")
async def accept(capture_id: str, index: int, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    return await executor.accept_suggestion(db, capture_id, index, user_id=user_id)


@router.get("/search")
async def do_search(
    q: str = Query(..., min_length=1),
    limit: int = Query(15, ge=1, le=100),
    user_id: str = Depends(current_user_id),
    db=Depends(get_db),
):
    return await search.hybrid_search(db, q, limit, user_id=user_id)


@router.post("/ask")
async def do_ask(body: AskIn, user_id: str = Depends(current_user_id), db=Depends(get_db)):
    return await search.ask(db, body.question, user_id=user_id)
