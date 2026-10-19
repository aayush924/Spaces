# MySpaces API Contract (v1)

Base URL: `http://localhost:8000` in development.
Every endpoint except `GET /health` requires `Authorization: Bearer <API_TOKEN>`.

Conventions
- JSON keys are **snake_case**.
- IDs are strings (`"id"`).
- Timestamps are ISO-8601 UTC with a `Z` suffix, e.g. `"2026-10-08T22:10:00Z"` (may include fractional seconds).
- Calendar dates (`due_date`, `date`) are `"YYYY-MM-DD"` strings.
- Errors return a non-2xx status with body `{"detail": "message"}`.

---

## Models

```jsonc
// Note
{ "id": "…", "text": "…", "title": "Garage bike storage", "tags": ["garage","idea"],
  "created_at": "…", "updated_at": "…" }

// ListSummary
{ "id": "…", "name": "Costco", "slug": "costco", "kind": "shopping",   // shopping | wishlist | custom
  "item_count": 5, "open_count": 3, "created_at": "…" }

// ListItem
{ "id": "…", "list_id": "…", "text": "paper towels", "quantity": "2" /* or null */,
  "done": false, "created_at": "…" }

// Todo
{ "id": "…", "text": "call dentist", "due_date": "2026-10-09", "done": false,
  "done_at": null /* or timestamp */, "created_at": "…" }

// ExecutedAction  (one per thing the AI did)
{ "type": "note" | "list_add" | "todo_add" | "todo_complete" | "list_item_remove",
  "summary": "2 items → Costco",
  "confidence": 0.93,
  "note_id": "…" | null,          // for type == note
  "list_id": "…" | null,          // for list ops
  "list_name": "Costco" | null,
  "due_date": "2026-10-09" | null,// for todo ops
  "items": ["eggs", "paper towels"] }  // item/todo texts affected (empty for notes)

// Suggestion  ("Did you mean…" chip for low-confidence routing)
{ "label": "Add “milk” to Costco", "list_name": "Costco", "items": ["milk"] }

// CaptureResponse
{ "capture_id": "…", "summary": "✓ 2 items → Costco · ✓ 1 todo for Fri Oct 9",
  "actions": [ExecutedAction], "suggestions": [Suggestion] }

// Capture (history entry)
{ "id": "…", "raw_text": "…", "summary": "…", "actions": [ExecutedAction],
  "suggestions": [Suggestion], "undone": false, "created_at": "…" }

// SearchResult
{ "note": Note, "score": 0.0312, "match": "semantic" | "keyword" | "both" }

// AskResponse
{ "answer": "You had two ideas about the garage… [1][2]", "citations": [Note] }
```

---

## Endpoints

| Method | Path | Body / Query | Returns |
|---|---|---|---|
| GET | `/health` | – | `{"status":"ok","db":true}` |
| POST | `/capture` | `{"text": str, "timezone": "America/Los_Angeles", "client_now": iso-timestamp?}` | `CaptureResponse` |
| GET | `/captures` | `?limit=20` | `[Capture]` (newest first) |
| POST | `/capture/{id}/undo` | – | `{"undone": true}` |
| POST | `/capture/{id}/suggestions/{index}/accept` | – | `CaptureResponse` (updated) – turns the fallback note into list items |
| GET | `/search` | `?q=…&limit=20` | `[SearchResult]` |
| POST | `/ask` | `{"question": str}` | `AskResponse` |
| GET | `/notes` | `?limit=50&before=<iso timestamp>` | `[Note]` newest first |
| POST | `/notes` | `{"text": str, "title"?: str, "tags"?: [str]}` | `Note` |
| GET | `/notes/{id}` | – | `Note` |
| PATCH | `/notes/{id}` | `{"text"?, "title"?, "tags"?}` | `Note` |
| DELETE | `/notes/{id}` | – | `204` |
| GET | `/lists` | – | `[ListSummary]` |
| POST | `/lists` | `{"name": str, "kind"?: "shopping"\|"wishlist"\|"custom"}` | `ListSummary` |
| DELETE | `/lists/{id}` | – | `204` (deletes items too) |
| GET | `/lists/{id}/items` | – | `[ListItem]` (open first, then done) |
| POST | `/lists/{id}/items` | `{"text": str, "quantity"?: str}` | `ListItem` |
| PATCH | `/lists/{id}/items/{item_id}` | `{"text"?, "quantity"?, "done"?}` | `ListItem` |
| DELETE | `/lists/{id}/items/{item_id}` | – | `204` |
| DELETE | `/lists/{id}/items?done=true` | – | `{"deleted": n}` (clear completed) |
| GET | `/todos` | `?date=YYYY-MM-DD` **or** `?overdue_before=YYYY-MM-DD` | `[Todo]` |
| POST | `/todos` | `{"text": str, "due_date": "YYYY-MM-DD"}` | `Todo` |
| PATCH | `/todos/{id}` | `{"text"?, "due_date"?, "done"?}` | `Todo` |
| DELETE | `/todos/{id}` | – | `204` |

`overdue_before` returns **not done** todos with `due_date < overdue_before` (the client passes its local "today").
