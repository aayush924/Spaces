# MySpaces — Comprehensive Project Documentation & Progress Report

**Document Purpose**: Full record of all architecture decisions, implemented components, test results, and current project status up to this point. Serves as the primary onboarding and state restoration document.  
**Date**: October 2026 (Updated Session 2)  
**Status**: 
- **Backend (FastAPI + MongoDB + Gemini + Hybrid Search)**: 100% Complete & Tested (18/18 tests passing offline)
- **iOS App (SwiftUI + XcodeGen)**: 100% Complete & Tested (22/22 unit tests passing, clean build on iOS 27 simulator, app launch verified)
- **Remaining**: Live end-to-end run with real MongoDB Atlas + Gemini API credentials

---

## 1. Project Overview & Vision

**MySpaces** is an intelligent, voice-first and text-first iOS thought-journal application designed to minimize cognitive load. Instead of requiring the user to manually organize thoughts into folders, separate shopping apps, and task managers, MySpaces accepts natural language input (typed or spoken) and automatically routes intents to the correct domain:

1. **Thoughts & Ideas** $\rightarrow$ Saved as **Notes**, embedded into a high-dimensional vector space, and retrievable via concept-based semantic search or keyword search.
2. **List Items** $\rightarrow$ Routed to shopping or custom lists (e.g., "Costco", "Walmart", "Wish List", or dynamically created lists like "Target" or "Trader Joe's").
3. **Dated Action Items** $\rightarrow$ Extracted and scheduled as **Todos** for specific dates (e.g., "today", "tomorrow", "next Friday").
4. **Multi-Intent Support** $\rightarrow$ A single spoken phrase (e.g., *"Add paper towels to Costco and tomorrow call the dentist, also had an idea about a solar bike charger"*) is automatically partitioned into list items, a dated todo, and a distinct note.
5. **Full Undo Capabilities** $\rightarrow$ Every capture is tracked with an audit trail of exact database effects, allowing a 1-tap undo of all side-effects.
6. **Concept & Phrase Search ("Ask" mode)** $\rightarrow$ Hybrid search fusing semantic vectors and exact keyword matches using Reciprocal Rank Fusion (RRF), plus a generative Q&A mode that answers questions citing user notes.

---

## 2. System Architecture & Tech Stack

```mermaid
flowchart TB
    subgraph Client ["iOS Client (SwiftUI 17+)"]
        Voice[Audio Engine / SFSpeechRecognizer]
        UI[TabView: Lists | Search | New | Todos | Settings]
        Storage[AppSettings + Keychain]
        APIClient[APIClient: Bearer Auth + ISO Dates]
    end

    subgraph Backend ["FastAPI Python Backend (Local Mac / Cloud Run)"]
        Auth[Bearer Token Security]
        Router[Gemini Intent Router + 15-Day Calendar Reference]
        Executor[Action Executor + Effect Tracker]
        HybridEngine[Hybrid Search Engine + Reciprocal Rank Fusion]
        Services[Fuzzy List Matcher + Embedding Service]
    end

    subgraph External ["External Services & Storage"]
        Atlas[(MongoDB Atlas M0 Free Tier)]
        GeminiChat[Gemini 2.5/3.x Flash: Structured JSON]
        GeminiEmbed[Gemini Embedding 2: 768-dim Vectors]
    end

    Voice --> UI
    UI --> APIClient
    APIClient -->|HTTPS / JSON| Auth
    Auth --> Router
    Auth --> Executor
    Auth --> HybridEngine

    Router --> GeminiChat
    Router --> Services
    Services --> GeminiEmbed
    Executor --> Atlas
    HybridEngine --> Atlas
    HybridEngine --> GeminiEmbed
```

### Key Technical Decisions:
- **Backend Stack**: Python 3.14, FastAPI, `AsyncMongoClient` (PyMongo native async, not Motor), `google-genai` SDK, `pydantic-settings`.
- **Gemini Embeddings Model**: Configured for `gemini-embedding-2` with 768 output dimensions. Handled prompt-prefix requirements (`task: search result | query: ...` vs `title: ... | text: ...`) with automatic fallback to legacy `gemini-embedding-001`.
- **MongoDB Atlas M0 Hybrid Search**: Free-tier Atlas M0 clusters do not support MongoDB 8.1+ `$rankFusion` pipeline stage. Implemented dual parallel query execution (`$vectorSearch` + `$search`) with Python-side **Reciprocal Rank Fusion (RRF)**. In addition, an in-process cosine similarity + BM25-lite search was implemented for offline tests, local databases, or when Atlas search indexes are still building.
- **Dynamic Search Index Bootstrap**: On application startup, the backend automatically registers Atlas Vector Search (`notes_vector`) and Atlas Text Search (`notes_text`) indexes via `create_search_indexes`.
- **Date Handling in AI**: To prevent hallucinations and math errors during relative date parsing ("tomorrow", "next Monday"), the router injects a dynamically generated 15-day reference calendar in the user's specific local timezone into the prompt.
- **Fail-Safe Fallback**: If the Gemini API is unreachable or times out, the backend automatically runs a deterministic regex/rule-based intent parser (`rule_route`). If that also fails, the raw text is preserved as a note. No user input is ever lost.

---

## 3. Detailed Component Breakdown & What Has Been Built

### A. Backend Layer (`backend/`)

1. **`backend/app/config.py`**:
   - Centralized typed Pydantic settings loading from `.env`.
   - Configurable models (`GEMINI_CHAT_MODEL`, `GEMINI_EMBED_MODEL`), embedding dimension (768), RRF weights (`semantic_weight=0.65`, `keyword_weight=0.35`, `semantic_min_score=0.3`), and `low_confidence_threshold=0.55`.

2. **`backend/app/db.py`**:
   - Connection lifecycle management with `AsyncMongoClient`.
   - Index verification for `notes`, `lists`, `list_items`, `todos`, and `captures`.
   - Programmatic Atlas Search index bootstrapping (`notes_vector` and `notes_text`).
   - Default list seeding: `Costco` (shopping), `Walmart` (shopping), `Wish List` (wishlist).
   - ISO-8601 formatting utilities and collection schema serializers.

3. **`backend/app/ai/schemas.py`**:
   - Pydantic models enforcing structured JSON outputs from Gemini: `RoutedAction`, `RouterResult`, `AskAnswer`.

4. **`backend/app/ai/gemini.py`**:
   - Clean facade over `google.genai.Client`.
   - Structured JSON generation (`generate_json`) with JSON Schema validation.
   - Vector embedding generation with unit-norm normalization and dual support for `gemini-embedding-2` and `gemini-embedding-001`.

5. **`backend/app/ai/router.py`**:
   - Context builder calculating local timezone calendar.
   - Comprehensive system prompt with few-shot examples for compound utterances.
   - Sanitization layer validating dates within a 1-year window and bounding confidence scores.
   - Rule-based backup router (`rule_route`) using regex for zero-downtime capture.

6. **`backend/app/services.py`**:
   - Fuzzy list matching (`find_list`): identifies matching lists even with informal input ("my costco list" $\rightarrow$ "Costco").
   - List auto-creation (`create_list`, `resolve_list`): automatically initializes new lists mentioned by the user.
   - Note creation and background embedding generation (`create_note`, `embed_note`).
   - Text similarity scoring (Jaccard + SequenceMatcher).

7. **`backend/app/executor.py`**:
   - Action dispatching: `note`, `list_add`, `list_item_remove`, `todo_add`, `todo_complete`.
   - Granular effect tracking: logs IDs of created notes, items, lists, and completed todos into `captures.effects`.
   - Transactional undo (`undo_capture`): deletes created items, un-completes modified todos, restores deleted list items, and cleans up empty auto-created lists.
   - Low-confidence handling: inputs with $<55\%$ confidence (e.g. "milk") are stored as notes and accompanied by interactive "Did you mean: Add to Costco?" suggestion chips. Accepting a suggestion converts the note into list items.

8. **`backend/app/search.py`**:
   - Vector search query generator (`RETRIEVAL_QUERY`).
   - Reciprocal Rank Fusion algorithm (`rrf_merge`) combining semantic and keyword rank lists.
   - Dual search paths: Atlas native aggregation pipeline vs in-process vector cosine + token BM25 scorer.
   - Generative Ask engine (`ask`): retrieves top-$k$ notes and prompts Gemini to formulate an answer with numbered citations `[1]`, `[2]`.

9. **`backend/app/auth.py` & API Routes (`backend/app/routes/`)**:
   - Bearer token authentication via constant-time comparison (`secrets.compare_digest`).
   - `capture.py`: `/capture`, `/captures`, `/capture/{id}/undo`, `/capture/{id}/suggestions/{index}/accept`, `/search`, `/ask`.
   - `crud.py`: Full CRUD for `/notes`, `/lists`, `/lists/{id}/items`, `/todos`.
   - `main.py`: FastAPI app initialization, CORS, and `/health` probe.

10. **Backend DevOps & Tooling**:
    - `Dockerfile`: Multi-stage container ready for Google Cloud Run deployment.
    - `Makefile`: Targets for `install`, `dev`, `test`, `test-live`, `models`, `reembed`.
    - `scripts/list_models.py`: Utility to query Gemini API and print active model tags.
    - `scripts/reembed.py`: Backfill script for embedding unindexed notes.

---

## 4. Verification & Testing Status

### Automated Backend Test Suite:
All tests are implemented using `pytest` and `mongomock` (with a custom async adapter) + a deterministic vector space simulator.

```bash
cd backend && .venv/bin/python -m pytest -q -p no:warnings
```
**Results**:
- **18 passed, 14 deselected** (0.11s execution time)
- **Coverage**:
  - `test_health_and_auth`: Healthcheck endpoint and 401 unauthorized protection.
  - `test_default_lists_seeded`: Initial database seeding.
  - `test_ai_multi_intent_capture_and_undo`: Multi-intent routing (Costco + Tomorrow Todo) and full undo.
  - `test_new_list_is_auto_created_and_removed_on_undo`: Auto-creation and rollback of new lists.
  - `test_duplicate_items_are_not_added_twice`: Item deduplication logic.
  - `test_low_confidence_becomes_note_with_suggestion`: Suggestion chip generation and conversion.
  - `test_todo_complete_and_undo`: Natural language task completion and un-completing on undo.
  - `test_list_item_remove_and_undo_restores`: Natural language list item removal and restoration.
  - `test_rule_fallback_when_ai_unavailable`: Regex rule-based capture when AI is down.
  - `test_reference_calendar_contains_tomorrow`: Calendar generation and timezone sanity.
  - `test_concept_search_finds_note_without_shared_keywords`: Semantic vector search without shared tokens ("storing bicycles" $\rightarrow$ "pegboard bike wall").
  - `test_exact_phrase_search`: Phrase matching boost.
  - `test_keyword_search_still_works_when_embeddings_fail`: Graceful degradation on embedding outage.
  - `test_ask_returns_answer_and_citations`: Generative RAG Q&A with citations.
  - `test_notes_crud`: Full notes lifecycle.
  - `test_lists_and_items_crud`: Lists and items lifecycle including bulk cleanup.
  - `test_todos_crud_and_overdue`: Daily todo fetching and overdue queries.
- **Live Golden Set (`tests/test_router_golden.py`)**:
  - 14 real-world benchmark phrases configured for end-to-end testing against live Gemini API (skips cleanly when `GEMINI_API_KEY` is omitted).

---

## 5. iOS Client Status (`ios/`)

The iOS client is designed in Swift 5 / SwiftUI with iOS 17+ Observation (`@Observable`) and no external third-party dependencies.

### Completed iOS Components:
1. **`ios/project.yml`**:
   - XcodeGen specification with targets for `MySpaces` (App) and `MySpacesTests`.
   - Configured privacy descriptions for `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, and `NSLocalNetworkUsageDescription`.
   - Development `NSAppTransportSecurity` exceptions for localhost / LAN debugging.
2. **`ios/MySpaces/Networking/`**:
   - `JSONCoding.swift`: Flexible date decoding strategy supporting standard ISO8601 strings both with and without fractional seconds.
   - `Models.swift`: Swift `Codable` structs matching the backend API contract (`Note`, `ListSummary`, `ListItem`, `Todo`, `ExecutedAction`, `Suggestion`, `CaptureResponse`, `Capture`, `SearchResult`, `AskResponse`).
   - `APIClient.swift`: Asynchronous networking client supporting authentication headers, error mapping, and REST methods.
3. **`ios/MySpaces/Speech/SpeechRecognizer.swift`**:
   - Live speech recognition using `SFSpeechRecognizer` and `AVAudioEngine`.
   - On-device speech recognition prioritization where available.
   - Live transcription stream into text input buffer.
4. **`ios/MySpaces/Storage/`**:
   - `Keychain.swift`: Secure storage for the backend Bearer token.
   - `AppSettings.swift`: Observable settings manager storing server URL and sync preferences.
5. **`ios/MySpaces/Features/Capture/`**:
   - `CaptureView.swift` & `CaptureViewModel.swift`: Main capture screen with large text editor, hold-to-talk / toggle mic button, action summary cards with status icons, Undo button, interactive suggestion chips, and recent capture history.
6. **`ios/MySpaces/Features/Search/`**:
   - `SearchView.swift` & `SearchViewModel.swift`: Real-time debounced hybrid search bar, segmented control for Direct Search vs Ask Mode, result item views, and citation link navigation.
7. **`ios/MySpaces/Features/Notes/`**:
   - `NoteDetailView.swift`: Note inspector allowing viewing, inline editing of title, body, tags, and deletion.
8. **`ios/MySpaces/Features/Lists/`**:
   - `ListsView.swift` & `ListsViewModel.swift`: Displays all lists with open item counts, sheet to create new lists, and swipe-to-delete.
   - `ListDetailView.swift`: Item checklist with instant checkbox toggles, inline quick-add, swipe-to-delete, and "Clear completed". Supports `init(listID:name:)` for direct deep-linking from Capture result cards.
9. **`ios/MySpaces/Features/Todos/`**:
   - `TodosView.swift` & `TodosViewModel.swift`: Segmented day selector (Today, Tomorrow, Pick date), dedicated **Overdue** section with swipe-to-reschedule to today, quick-add for selected date, and tap-to-complete.
10. **`ios/MySpaces/Features/Settings/`**:
    - `SettingsView.swift`: Server URL input, Keychain-backed API token field, and a "Test connection" feature diagnosing `/health`, database connectivity, and `/lists` authorization independently.
11. **`ios/MySpaces/Shared/SharedViews.swift`**:
    - Reusable UI elements, tag chips, and action badges.
12. **`ios/MySpaces/App/MySpacesApp.swift`**:
    - Root `TabView` coordinating Lists, Search, New, Todos, and Settings tabs (with New as landing page). Automatically redirects to Settings on first launch if unconfigured.
13. **`ios/MySpacesTests/`**:
    - `ModelDecodingTests.swift`: Comprehensive unit tests for model decoding (all models, timestamps with/without fractional seconds, timezone offsets, and date formatting helpers).
    - `APIClientTests.swift`: URLProtocol-based network tests verifying request construction, headers, escaping, error mapping, and responses without hitting an external server.

### Automated iOS Test & Build Results:
- **Command**:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MySpaces.xcodeproj -scheme MySpaces -destination 'platform=iOS Simulator,name=iPhone 17' build test
  ```
- **Build Status**: `** BUILD SUCCEEDED **`
- **Test Status**: `** TEST SUCCEEDED **` (22/22 unit tests passed)
- **Simulator Launch**: Booted and launched on iPhone 17 (iOS 27.0) simulator. Verified first-launch flow directly into Settings screen.

---

## 6. How to Resume & Run Live

Both the backend and frontend are complete and unit-tested offline. The remaining milestone is live integration.

### Step 1: Supply User Secrets
Create your `.env` file in `backend/`:
```bash
cd backend
cp .env.example .env
```
Populate the three values:
1. `MONGODB_URI`: From MongoDB Atlas (create free M0 cluster $\rightarrow$ Database Access $\rightarrow$ Network Access $\rightarrow$ copy connection string).
2. `GEMINI_API_KEY`: From [Google AI Studio](https://aistudio.google.com/apikey).
3. `API_TOKEN`: Choose a secure secret string (e.g. `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`).

### Step 2: Start Backend
```bash
cd backend
source .venv/bin/activate
make dev
```
Confirm health status at `http://localhost:8000/health`:
```json
{"status": "ok", "db": true, "atlas_search": true}
```

### Step 3: Run Live Golden Set Tests
```bash
make test-live
```
Verifies all 14 sample user utterances against your live Gemini API model key.

### Step 4: Run iOS App in Simulator & Connect
1. In Xcode or terminal:
   ```bash
   cd ios
   open MySpaces.xcodeproj
   ```
2. Run on iPhone 17 Simulator.
3. In the app's **Settings** tab:
   - Server URL: `http://localhost:8000`
   - API Token: Paste your `API_TOKEN`
   - Tap **Test connection** (should indicate "Connected · 3 lists").
4. Switch to **New** tab and test live dictation or typing!

---

## 9. Session 3 — 2026/2027 Warm Dark Humanist UI Redesign (Oct 18, 2026)

### What was done
- Implemented the **Warm Dark Humanist** iOS UI redesign matching the reference mockups without changing backend routes or iOS model/networking structures:
  - Added [Theme.swift](file:///Users/aayushparikh/desktop/projects/MySpaces/ios/MySpaces/Shared/Theme.swift) with deep obsidian backgrounds (`#1A1816`), elevated card surfaces (`#221F1B`), fine sand borders (`#3E3730`), terracotta/apricot/ochre/sienna/taupe accents, `Georgia-Bold` editorial serif headings (`Theme.serifTitle`), `OrganicCheckbox`, and `ShowcaseData` fallback seed data.
  - Updated [MySpacesApp.swift](file:///Users/aayushparikh/desktop/projects/MySpaces/ios/MySpaces/App/MySpacesApp.swift) with the **Futuristic Floating Navigation Dock** (`Lists`, `Search`, `New`, `Notes`, `Settings`).
  - Redesigned [ListsView.swift](file:///Users/aayushparikh/desktop/projects/MySpaces/ios/MySpaces/Features/Lists/ListsView.swift) (`Spaces` screen with `Today | Tomorrow | Lists` segmented capsule, expanded `'Costco' List` with inline items and glowing terracotta progress bar, `Wish List`, and `TOMORROW` section with `10:00 AM` clock badge and tagged todos).
  - Redesigned [CaptureView.swift](file:///Users/aayushparikh/desktop/projects/MySpaces/ios/MySpaces/Features/Capture/CaptureView.swift) (`New` screen with `A\` monogram AI result card, `Undo` pill, dashed `Suggestions:` box, and floating mic button).
  - Added [NotesListView.swift](file:///Users/aayushparikh/desktop/projects/MySpaces/ios/MySpaces/Features/Notes/NotesListView.swift) (`Notes` screen with tag pills and relative timestamps) and updated [NoteDetailView.swift](file:///Users/aayushparikh/desktop/projects/MySpaces/ios/MySpaces/Features/Notes/NoteDetailView.swift), [SearchView.swift](file:///Users/aayushparikh/desktop/projects/MySpaces/ios/MySpaces/Features/Search/SearchView.swift), [SettingsView.swift](file:///Users/aayushparikh/desktop/projects/MySpaces/ios/MySpaces/Features/Settings/SettingsView.swift), and [TodosView.swift](file:///Users/aayushparikh/desktop/projects/MySpaces/ios/MySpaces/Features/Todos/TodosView.swift).
- Verified with `xcodegen generate` and `xcodebuild build test` on iPhone 17 Simulator (**BUILD SUCCEEDED · 22/22 unit tests passing**) and verified live in Simulator.
