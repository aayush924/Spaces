"""Live golden-set tests for the intent router. Hits real Gemini.

Run with:  make test-live   (requires GEMINI_API_KEY in .env)
"""
from datetime import date

import pytest

from app.ai import router
from app.ai.router import RouteContext
from app.config import get_settings

pytestmark = [pytest.mark.live, pytest.mark.asyncio]

TODAY = date(2026, 10, 8)  # Thursday
LISTS = ["Costco", "Walmart", "Wish List"]

# (utterance, expected list of (type, list_name|None, due_date|None, min_items))
GOLDEN = [
    ("add eggs and paper towels to costco", [("list_add", "Costco", None, 2)]),
    ("wishlist: kindle scribe", [("list_add", "Wish List", None, 1)]),
    ("put AirPods Max on my wish list", [("list_add", "Wish List", None, 1)]),
    ("grab bananas, oat milk and dish soap at walmart", [("list_add", "Walmart", None, 3)]),
    ("tomorrow: gym, email Raj", [("todo_add", None, "2026-10-09", 2)]),
    ("tomorrow I need to call the dentist and renew my registration", [("todo_add", None, "2026-10-09", 2)]),
    ("also add pick up dry cleaning to tomorrow", [("todo_add", None, "2026-10-09", 1)]),
    ("on saturday I want to clean the garage", [("todo_add", None, "2026-10-10", 1)]),
    ("next monday submit the expense report", [("todo_add", None, "2026-10-12", 1)]),
    ("idea: app that tracks plant watering by photo", [("note", None, None, 0)]),
    ("I've been thinking that I'm happiest when I walk in the mornings", [("note", None, None, 0)]),
    (
        "grab milk at walmart and also I had a thought about a bike rack for the garage",
        [("list_add", "Walmart", None, 1), ("note", None, None, 0)],
    ),
    ("add sunscreen to my target list", [("list_add", "Target", None, 1)]),
    ("todo call mom", [("todo_add", None, "2026-10-08", 1)]),
]


@pytest.fixture(autouse=True)
def _require_key():
    get_settings.cache_clear()
    if not get_settings().gemini_api_key:
        pytest.skip("GEMINI_API_KEY not set")


@pytest.mark.parametrize("text,expected", GOLDEN)
async def test_router_golden(text, expected):
    ctx = RouteContext(today=TODAY, list_names=LISTS)
    actions, used_ai = await router.route(text, ctx)
    assert used_ai, "router fell back to rules (AI call failed)"
    got = sorted(actions, key=lambda a: a.type)
    want = sorted(expected, key=lambda e: e[0])
    assert [a.type for a in got] == [e[0] for e in want], [a.model_dump() for a in actions]
    for a, (typ, list_name, due, min_items) in zip(got, want, strict=True):
        if list_name:
            assert (a.list_name or "").lower() == list_name.lower()
        if due:
            assert a.due_date == due
        assert len(a.items) >= min_items
