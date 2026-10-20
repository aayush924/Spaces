"""End-to-end API tests with a fake Gemini and in-memory Mongo."""
from datetime import date, timedelta

from app.ai.router import RouteContext, rule_route
from app.ai.schemas import RoutedAction, RouterResult

TZ = "America/Los_Angeles"
NOW = "2026-10-08T22:00:00-07:00"  # Thursday Oct 8 (local)
TODAY = date(2026, 10, 8)
TOMORROW = (TODAY + timedelta(days=1)).isoformat()


def cap(client, text):
    r = client.post("/capture", json={"text": text, "timezone": TZ, "client_now": NOW})
    assert r.status_code == 200, r.text
    return r.json()


def lists_by_name(client):
    return {l["name"]: l for l in client.get("/lists").json()}


# --------------------------------------------------------------------------- auth / health


def test_health_and_auth(client):
    assert client.get("/health").json()["status"] == "ok"
    r = client.get("/lists", headers={"Authorization": "Bearer wrong"})
    assert r.status_code == 401


def test_default_lists_seeded(client):
    assert {"Costco", "Walmart", "Wish List"} <= set(lists_by_name(client))


# --------------------------------------------------------------------------- capture via AI


def test_ai_multi_intent_capture_and_undo(client, fake_ai):
    text = "add eggs and paper towels to costco and tomorrow call the dentist"
    fake_ai.router_results[text] = RouterResult(
        actions=[
            RoutedAction(type="list_add", list_name="costco list", items=["eggs", "paper towels"], confidence=0.97),
            RoutedAction(type="todo_add", due_date=TOMORROW, items=["call the dentist"], confidence=0.95),
        ]
    )
    out = cap(client, text)
    assert [a["type"] for a in out["actions"]] == ["list_add", "todo_add"]
    assert out["actions"][0]["list_name"] == "Costco"  # fuzzy-resolved
    assert "Tomorrow" in out["actions"][1]["summary"]

    costco = lists_by_name(client)["Costco"]
    assert costco["open_count"] == 2
    todos = client.get("/todos", params={"date": TOMORROW}).json()
    assert [t["text"] for t in todos] == ["call the dentist"]

    # history
    hist = client.get("/captures").json()
    assert hist[0]["id"] == out["capture_id"] and hist[0]["undone"] is False

    # undo everything
    assert client.post(f"/capture/{out['capture_id']}/undo").json() == {"undone": True}
    assert lists_by_name(client)["Costco"]["open_count"] == 0
    assert client.get("/todos", params={"date": TOMORROW}).json() == []


def test_new_list_is_auto_created_and_removed_on_undo(client, fake_ai):
    text = "add sunscreen to my target list"
    fake_ai.router_results[text] = RouterResult(
        actions=[RoutedAction(type="list_add", list_name="Target", list_kind="shopping", items=["sunscreen"], confidence=0.9)]
    )
    out = cap(client, text)
    assert "(new list)" in out["actions"][0]["summary"]
    assert lists_by_name(client)["Target"]["kind"] == "shopping"
    client.post(f"/capture/{out['capture_id']}/undo")
    assert "Target" not in lists_by_name(client)


def test_duplicate_items_are_not_added_twice(client, fake_ai):
    text = "add eggs to costco"
    fake_ai.router_results[text] = RouterResult(
        actions=[RoutedAction(type="list_add", list_name="Costco", items=["eggs"], confidence=0.95)]
    )
    cap(client, text)
    out = cap(client, text)
    assert out["actions"][0]["summary"].startswith("Already on Costco")
    assert lists_by_name(client)["Costco"]["open_count"] == 1


def test_low_confidence_becomes_note_with_suggestion(client, fake_ai):
    fake_ai.router_results["milk"] = RouterResult(
        actions=[RoutedAction(type="list_add", list_name="Costco", items=["milk"], confidence=0.3)]
    )
    out = cap(client, "milk")
    assert [a["type"] for a in out["actions"]] == ["note"]
    assert out["suggestions"][0]["list_name"] == "Costco"

    accepted = client.post(f"/capture/{out['capture_id']}/suggestions/0/accept").json()
    assert [a["type"] for a in accepted["actions"]] == ["list_add"]  # fallback note removed
    assert accepted["suggestions"] == []
    assert client.get("/notes").json() == []
    assert lists_by_name(client)["Costco"]["open_count"] == 1


def test_todo_complete_and_undo(client, fake_ai):
    client.post("/todos", json={"text": "call the dentist", "due_date": TODAY.isoformat()})
    text = "finished calling the dentist"
    fake_ai.router_results[text] = RouterResult(
        actions=[RoutedAction(type="todo_complete", items=["call the dentist"], confidence=0.85)]
    )
    out = cap(client, text)
    assert out["actions"][0]["items"] == ["call the dentist"]
    assert client.get("/todos", params={"date": TODAY.isoformat()}).json()[0]["done"] is True
    client.post(f"/capture/{out['capture_id']}/undo")
    assert client.get("/todos", params={"date": TODAY.isoformat()}).json()[0]["done"] is False


def test_list_item_remove_and_undo_restores(client, fake_ai):
    costco = lists_by_name(client)["Costco"]
    client.post(f"/lists/{costco['id']}/items", json={"text": "eggs"})
    text = "take eggs off the costco list"
    fake_ai.router_results[text] = RouterResult(
        actions=[RoutedAction(type="list_item_remove", list_name="Costco", items=["eggs"], confidence=0.9)]
    )
    out = cap(client, text)
    assert client.get(f"/lists/{costco['id']}/items").json() == []
    client.post(f"/capture/{out['capture_id']}/undo")
    assert [i["text"] for i in client.get(f"/lists/{costco['id']}/items").json()] == ["eggs"]


# --------------------------------------------------------------------------- rule fallback (Gemini down)


def test_rule_fallback_when_ai_unavailable(client):
    out = cap(client, "add bananas and oat milk to my walmart list")
    assert out["actions"][0]["list_name"] == "Walmart"
    assert out["actions"][0]["items"] == ["bananas", "oat milk"]

    out = cap(client, "tomorrow I need to gym and email Raj")
    assert out["actions"][0]["due_date"] == TOMORROW
    assert out["actions"][0]["items"] == ["gym", "email Raj"]

    out = cap(client, "random musing about life")
    assert out["actions"][0]["type"] == "note"


def test_rule_route_unit():
    ctx = RouteContext(today=TODAY, list_names=[])
    a = rule_route("add kindle to my wishlist", ctx)[0]
    assert a.type == "list_add" and a.list_name == "Wish List"
    a = rule_route("add pick up dry cleaning to tomorrow", ctx)[0]
    assert a.type == "todo_add" and a.due_date == TOMORROW and a.items == ["pick up dry cleaning"]


def test_reference_calendar_contains_tomorrow():
    ctx = RouteContext.build(TZ, None, [])
    cal = ctx.calendar().splitlines()
    assert cal[0].endswith("today") and cal[1].endswith("tomorrow") and len(cal) == 15


# --------------------------------------------------------------------------- search / ask


def _seed_notes(client):
    texts = [
        "What if the garage had a pegboard wall so the bikes hang vertically",
        "A plant watering app that uses photos to detect thirsty plants",
        "Book recommendation: The Pragmatic Programmer",
        "Remember the quarterly tax payment schedule",
        "Recipe idea: miso butter salmon",
    ]
    return [client.post("/notes", json={"text": t}).json() for t in texts]


def test_concept_search_finds_note_without_shared_keywords(client):
    notes = _seed_notes(client)
    res = client.get("/search", params={"q": "storing bicycles"}).json()
    assert res and res[0]["note"]["id"] == notes[0]["id"]
    assert res[0]["match"] in ("semantic", "both")


def test_exact_phrase_search(client):
    notes = _seed_notes(client)
    res = client.get("/search", params={"q": "miso butter salmon"}).json()
    assert res[0]["note"]["id"] == notes[4]["id"]
    assert res[0]["match"] == "both"


def test_keyword_search_still_works_when_embeddings_fail(client, fake_ai):
    fake_ai.embed_fails = True
    notes = _seed_notes(client)
    res = client.get("/search", params={"q": "pragmatic programmer"}).json()
    assert res[0]["note"]["id"] == notes[2]["id"]


def test_ask_returns_answer_and_citations(client):
    _seed_notes(client)
    out = client.post("/ask", json={"question": "what did I think about bike storage?"}).json()
    assert "[1]" in out["answer"]
    assert out["citations"][0]["text"].startswith("What if the garage")


# --------------------------------------------------------------------------- CRUD


def test_notes_crud(client):
    n = client.post("/notes", json={"text": "hello world idea", "tags": ["Misc"]}).json()
    assert n["title"] == "hello world idea" and n["created_at"].endswith("Z")
    n2 = client.patch(f"/notes/{n['id']}", json={"title": "Greeting", "tags": ["a", "B"]}).json()
    assert n2["title"] == "Greeting" and n2["tags"] == ["a", "b"]
    assert client.delete(f"/notes/{n['id']}").status_code == 204
    assert client.get(f"/notes/{n['id']}").status_code == 404
    assert client.get("/notes/not-an-id").status_code == 404


def test_lists_and_items_crud(client):
    lst = client.post("/lists", json={"name": "Trader Joe's", "kind": "shopping"}).json()
    item = client.post(f"/lists/{lst['id']}/items", json={"text": "dumplings", "quantity": "2"}).json()
    assert item["quantity"] == "2" and item["done"] is False
    item = client.patch(f"/lists/{lst['id']}/items/{item['id']}", json={"done": True}).json()
    assert item["done"] is True
    assert client.delete(f"/lists/{lst['id']}/items", params={"done": "true"}).json() == {"deleted": 1}
    assert client.delete(f"/lists/{lst['id']}").status_code == 204


def test_todos_crud_and_overdue(client):
    yesterday = (TODAY - timedelta(days=1)).isoformat()
    later_day = (TODAY + timedelta(days=3)).isoformat()
    t1 = client.post("/todos", json={"text": "old task", "due_date": yesterday}).json()
    client.post("/todos", json={"text": "today task", "due_date": TODAY.isoformat()})
    client.post("/todos", json={"text": "tomorrow task", "due_date": TOMORROW})
    client.post("/todos", json={"text": "future task", "due_date": later_day})
    overdue = client.get("/todos", params={"overdue_before": TODAY.isoformat()}).json()
    assert [t["text"] for t in overdue] == ["old task"]
    later = client.get("/todos", params={"after": TODAY.isoformat()}).json()
    assert [t["text"] for t in later] == ["tomorrow task", "future task"]
    t1 = client.patch(f"/todos/{t1['id']}", json={"done": True}).json()
    assert t1["done"] and t1["done_at"]
    assert client.get("/todos", params={"overdue_before": TODAY.isoformat()}).json() == []
    assert client.post("/todos", json={"text": "x", "due_date": "tomorrow"}).status_code == 422
    assert client.get("/todos").status_code == 422

