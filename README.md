# Spaces

An iOS thought journal that understands what you mean. Type or speak, and Spaces:

- saves **ideas as notes** you can later find **by concept** ("storing bikes" finds "pegboard wall in the garage"),
- adds items to **lists** ("add eggs and paper towels to my Costco list", "put AirPods on my wish list"),
- creates **dated todos** ("tomorrow I need to call the dentist", "also add dry cleaning to tomorrow"),
- does several of these from one sentence, with one-tap **Undo**,
- answers questions about your notes ("what ideas have I had about the garage?") with citations.

| Layer | Tech |
|---|---|
| iOS app | SwiftUI (iOS 17+), on-device speech recognition, Keychain |
| Backend | Python FastAPI, async PyMongo, `google-genai` |
| Data / search | MongoDB Atlas (free M0): Vector Search + Atlas Search, fused with RRF |
| AI | Gemini Flash (intent routing, Ask), Gemini Embedding (768-dim) |

Docs: [`docs/API.md`](docs/API.md) (API contract) · [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) · [`docs/PROJECT_HISTORY.md`](docs/PROJECT_HISTORY.md)

---

## 1. One-time setup

### MongoDB Atlas (free)
1. Create an account at <https://cloud.mongodb.com> → **Create** → **M0 Free** cluster.
2. **Database Access** → add a database user (username + password).
3. **Network Access** → **Add IP Address** → add your current IP (or `0.0.0.0/0` for testing only).
4. **Connect** → **Drivers** → **Python** → copy the `mongodb+srv://…` connection string.

The backend creates its collections and both search indexes (`notes_vector`, `notes_text`) on first start.
In Atlas → your cluster → **Search & Vector Search**, they show as *READY* within a minute or two.
Until then, search uses a built-in in-process fallback, so it works immediately either way.

### Gemini API key
Create a key at <https://aistudio.google.com/apikey>. A consumer Gemini AI Pro subscription does **not** include an API key;
the free API tier is plenty for a personal journal.

### Backend config
```bash
cd backend
cp .env.example .env
# edit .env: MONGODB_URI, GEMINI_API_KEY, and a random API_TOKEN:
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

## 2. Run the backend
```bash
cd backend
make install     # creates .venv and installs dependencies
make test        # offline tests (no Atlas/Gemini needed)
make models      # optional: list the Gemini models your key can use
make dev         # http://localhost:8000  — interactive docs at /docs
```
Optional: `make test-live` runs the router "golden set" against real Gemini.

## 3. Run the iOS app
```bash
brew install xcodegen          # once
cd ios
xcodegen generate
open Spaces.xcodeproj          # pick an iPhone simulator and press Run
```
Command-line build + tests (no need to change `xcode-select`):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Spaces.xcodeproj \
  -scheme Spaces -destination 'platform=iOS Simulator,name=iPhone 17' build test
```

In the app open **Settings**:
- **Server URL**: `http://localhost:8000` in the Simulator. On a real iPhone, use your Mac's LAN IP
  (`ipconfig getifaddr en0`), e.g. `http://192.168.1.20:8000`, with the phone on the same Wi-Fi.
- **API token**: the `API_TOKEN` from `backend/.env`.
- Tap **Test connection**.

To install on your own iPhone: in Xcode → target **Spaces** → **Signing & Capabilities**, choose your Apple ID team.

## 4. Try it
| Say / type on New (Capture) | Result |
|---|---|
| "Add bananas and oat milk to my Walmart list" | 2 items on Walmart |
| "Put a Kindle Scribe on my wish list" | Wish List item |
| "Tomorrow I need to call mom and book the dentist" | 2 todos for tomorrow |
| "Add pick up dry cleaning to tomorrow" | appended to tomorrow |
| "Idea: a pegboard wall in the garage so bikes hang vertically" | note |
| Search tab: "storing bicycles" | finds the pegboard note |
| Ask: "what ideas have I had about the garage?" | answer + cited notes |

## 5. Deploying later (Cloud Run)
`backend/Dockerfile` is ready to use. After deploying, put the HTTPS URL in the app's Settings and remove
`NSAllowsArbitraryLoads` from `ios/project.yml`.
