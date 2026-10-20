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
| Data / search | MongoDB Atlas: Vector Search + Atlas Search, fused with RRF |
| AI | Gemini Flash (intent routing, Ask), Gemini Embedding (768-dim) |
