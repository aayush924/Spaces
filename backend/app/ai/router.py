"""Intent router: turns a free-form utterance into a list of structured actions."""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from . import gemini
from .schemas import RoutedAction, RouterResult

log = logging.getLogger(__name__)


@dataclass
class RouteContext:
    today: date
    list_names: list[str]

    @staticmethod
    def build(timezone: str | None, client_now: datetime | None, list_names: list[str]) -> RouteContext:
        try:
            tz = ZoneInfo(timezone) if timezone else ZoneInfo("UTC")
        except (ZoneInfoNotFoundError, ValueError):
            tz = ZoneInfo("UTC")
        now = client_now.astimezone(tz) if client_now else datetime.now(tz)
        return RouteContext(today=now.date(), list_names=list_names)

    def calendar(self) -> str:
        """Reference calendar so the model never has to do date arithmetic."""
        lines = []
        for i in range(0, 15):
            d = self.today + timedelta(days=i)
            label = {0: "today", 1: "tomorrow"}.get(i, "")
            lines.append(f"{d.isoformat()} {d.strftime('%A')} {label}".rstrip())
        return "\n".join(lines)


SYSTEM_PROMPT = """You are the intent router for a personal thought-journal app.
Split the user's input into one or more ACTIONS. Output JSON only, matching the schema.

Action types:
- note: an idea, thought, reflection, observation, plan, or anything worth remembering.
  Fill note_text (the user's wording, lightly cleaned of filler like "um", "note to self"), title, tags.
- list_add: add items to a named list (shopping lists like Costco/Walmart, a wish list, or any other list).
  Fill list_name and items. If the list is new, also fill list_kind.
- list_item_remove: remove/cross off items from a list ("got the eggs", "take milk off the costco list").
- todo_add: tasks the user wants to do on a specific day ("tomorrow I need to…", "add X to tomorrow",
  "on Friday call mom"). Fill due_date and items (one task per item).
- todo_complete: the user says they finished tasks ("done with the dentist call"). Fill items and due_date if known.

Rules:
- Resolve every relative date using the REFERENCE CALENDAR. due_date must be YYYY-MM-DD.
- "todo"/"to-do" with no day means today. "my list for tomorrow" means a todo on tomorrow's date.
- Split compound inputs: "add eggs to costco and I had an idea about X" -> list_add + note.
- Split multiple items: "eggs, milk and paper towels" -> three items. Keep quantities in the item text ("2 gallons milk").
- Prefer an EXISTING list name when the user's words refer to it ("costco list", "my wishlist" -> "Wish List").
- "wish list"/"wishlist"/"I want" style requests -> list_add to "Wish List".
- If the input is only a bare item with no list or verb ("milk"), use list_add with your best-guess list
  and LOW confidence (<0.5).
- Never drop content. When in doubt, make it a note.
- confidence: 0.9+ when explicit, 0.6-0.8 when inferred, below 0.5 when guessing.
"""

FEW_SHOT = """EXAMPLES (dates assume today is 2026-01-15 Thursday)
Input: add paper towels and eggs to my costco list
Output: {"actions":[{"type":"list_add","list_name":"Costco","items":["paper towels","eggs"],"confidence":0.97}]}
Input: put the kindle scribe on my wishlist
Output: {"actions":[{"type":"list_add","list_name":"Wish List","items":["Kindle Scribe"],"confidence":0.96}]}
Input: tomorrow I need to call the dentist and renew my registration
Output: {"actions":[{"type":"todo_add","due_date":"2026-01-16","items":["call the dentist","renew registration"],"confidence":0.95}]}
Input: also add pick up dry cleaning to tomorrow
Output: {"actions":[{"type":"todo_add","due_date":"2026-01-16","items":["pick up dry cleaning"],"confidence":0.93}]}
Input: what if the garage had a pegboard wall so the bikes hang vertically
Output: {"actions":[{"type":"note","note_text":"What if the garage had a pegboard wall so the bikes hang vertically","title":"Garage pegboard bike wall","tags":["garage","home","idea"],"confidence":0.95}]}
Input: grab milk at walmart, and I had a thought: a plant watering app that uses photos
Output: {"actions":[{"type":"list_add","list_name":"Walmart","items":["milk"],"confidence":0.93},{"type":"note","note_text":"A plant watering app that uses photos","title":"Photo-based plant watering app","tags":["app idea","plants"],"confidence":0.92}]}
Input: add sunscreen to my target list
Output: {"actions":[{"type":"list_add","list_name":"Target","list_kind":"shopping","items":["sunscreen"],"confidence":0.94}]}
Input: finished calling the dentist
Output: {"actions":[{"type":"todo_complete","items":["call the dentist"],"confidence":0.85}]}
"""


def build_prompt(text: str, ctx: RouteContext) -> str:
    lists = ", ".join(ctx.list_names) or "(none)"
    return (
        f"{FEW_SHOT}\n"
        f"REFERENCE CALENDAR (the user's local dates):\n{ctx.calendar()}\n\n"
        f"EXISTING LISTS: {lists}\n\n"
        f"Input: {text}\nOutput:"
    )


async def route(text: str, ctx: RouteContext) -> tuple[list[RoutedAction], bool]:
    """Returns (actions, used_ai). Falls back to rules if Gemini is unavailable."""
    try:
        result = await gemini.generate_json(SYSTEM_PROMPT, build_prompt(text, ctx), RouterResult)
        actions = [a for a in result.actions if _is_meaningful(a)]
        if actions:
            return [_sanitize(a, ctx) for a in actions], True
        log.warning("Router returned no usable actions; falling back to rules")
    except Exception as exc:  # noqa: BLE001 - never lose a capture because the LLM failed
        log.warning("Router AI failed (%s); falling back to rules", exc)
    return [_sanitize(a, ctx) for a in rule_route(text, ctx)], False


def _is_meaningful(a: RoutedAction) -> bool:
    if a.type == "note":
        return bool((a.note_text or "").strip())
    return bool([i for i in a.items if i.strip()])


def _sanitize(a: RoutedAction, ctx: RouteContext) -> RoutedAction:
    a.items = [i.strip() for i in a.items if i.strip()]
    a.confidence = max(0.0, min(1.0, a.confidence))
    if a.type in ("todo_add",):
        a.due_date = _valid_date(a.due_date, ctx) or ctx.today.isoformat()
    elif a.type == "todo_complete":
        a.due_date = _valid_date(a.due_date, ctx)
    if a.type == "note":
        a.tags = [t.strip().lower() for t in a.tags if t.strip()][:6]
    return a


def _valid_date(value: str | None, ctx: RouteContext) -> str | None:
    if not value:
        return None
    try:
        d = date.fromisoformat(value)
    except ValueError:
        return None
    if abs((d - ctx.today).days) > 366:
        return None
    return d.isoformat()


# --------------------------------------------------------------------------- rule fallback

_ADD_TO_LIST = re.compile(
    r"^\s*(?:please\s+)?(?:add|put|throw)\s+(?P<items>.+?)\s+(?:to|on|onto|in)\s+(?:my|the)?\s*"
    r"(?P<list>[\w' ]+?)\s*(?:list)?\s*[.!]?\s*$",
    re.IGNORECASE,
)
_TODO = re.compile(
    r"^\s*(?:(?:add|put)\s+(?P<a>.+?)\s+(?:to|for|on)\s+(?:my\s+)?(?P<day1>today|tomorrow)(?:'s)?(?:\s+(?:list|todos?))?"
    r"|(?P<day2>today|tomorrow)\s*(?:,|:|-)?\s*(?:i\s+(?:need|have|want)\s+to\s+|todo:?\s*)?(?P<b>.+?))\s*[.!]?\s*$",
    re.IGNORECASE,
)


def _split_items(s: str) -> list[str]:
    parts = re.split(r",|\band\b|&", s)
    return [p.strip(" .") for p in parts if p.strip(" .")]


def rule_route(text: str, ctx: RouteContext) -> list[RoutedAction]:
    """Deterministic fallback used when Gemini is unavailable. Handles the common phrasings."""
    m = _TODO.match(text)
    if m:
        day = (m.group("day1") or m.group("day2")).lower()
        body = m.group("a") or m.group("b")
        due = ctx.today + timedelta(days=1 if day == "tomorrow" else 0)
        return [RoutedAction(type="todo_add", items=_split_items(body), due_date=due.isoformat(), confidence=0.7)]
    m = _ADD_TO_LIST.match(text)
    if m:
        list_name = m.group("list").strip()
        list_name = re.sub(r"\s*list$", "", list_name, flags=re.IGNORECASE)
        if list_name.lower() in ("wish", "wishlist"):
            list_name = "Wish List"
        return [RoutedAction(type="list_add", list_name=list_name, items=_split_items(m.group("items")), confidence=0.7)]
    return [RoutedAction(type="note", note_text=text.strip(), title=None, tags=[], confidence=0.5)]
