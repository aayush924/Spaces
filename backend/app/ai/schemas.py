"""Structured-output contract between the intent router (Gemini) and the executor."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

ActionType = Literal["note", "list_add", "todo_add", "todo_complete", "list_item_remove"]


class RoutedAction(BaseModel):
    type: ActionType = Field(description="What to do with this part of the user's input.")
    # --- note
    note_text: str | None = Field(
        default=None, description="For type=note: the thought, lightly cleaned up but in the user's own words."
    )
    title: str | None = Field(default=None, description="For type=note: a short 2-6 word title.")
    tags: list[str] = Field(default_factory=list, description="For type=note: 1-4 lowercase topical tags.")
    # --- lists
    list_name: str | None = Field(
        default=None,
        description="For list ops: the target list. Use an existing list name exactly when it matches.",
    )
    list_kind: Literal["shopping", "wishlist", "custom"] | None = Field(
        default=None, description="For list ops on a NEW list: what kind of list it is."
    )
    # --- shared by list + todo ops
    items: list[str] = Field(
        default_factory=list,
        description="For list/todo ops: one entry per item or task, short, keeping the user's wording.",
    )
    due_date: str | None = Field(
        default=None, description="For todo ops: absolute date YYYY-MM-DD resolved from the reference calendar."
    )
    confidence: float = Field(description="0-1 confidence that this action is what the user intended.")


class RouterResult(BaseModel):
    actions: list[RoutedAction]


class AskAnswer(BaseModel):
    answer: str
