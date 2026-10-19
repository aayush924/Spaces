import Foundation
import Observation

@MainActor
@Observable
final class CaptureViewModel {
    var text = ""
    private(set) var isSending = false
    /// The most recent capture result shown under the editor.
    private(set) var lastResponse: CaptureResponse? = nil
    private(set) var lastUndone = false
    private(set) var isMutating = false
    private(set) var recent: [Capture] = []
    private(set) var isLoadingRecent = false
    var recentError: String?
    var errorMessage: String?

    var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send(api: APIClient, isConfigured: Bool = true) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        if !isConfigured {
            lastResponse = Self.simulateLocalCapture(for: trimmed)
            lastUndone = false
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            let response = try await api.capture(text: trimmed, timeZone: .current, now: Date())
            lastResponse = response
            lastUndone = false
            text = ""
            await loadRecent(api: api, isConfigured: isConfigured)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func undoLast(api: APIClient, isConfigured: Bool = true) async {
        guard let response = lastResponse, !lastUndone else { return }
        if !isConfigured || response.captureId.hasPrefix("showcase-") {
            lastUndone = true
            return
        }
        do {
            try await undo(captureID: response.captureId, api: api)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    /// Undoes any capture (latest or from history) and updates local state.
    func undo(captureID: String, api: APIClient) async throws {
        isMutating = true
        defer { isMutating = false }
        _ = try await api.undoCapture(id: captureID)
        if lastResponse?.captureId == captureID { lastUndone = true }
        if let index = recent.firstIndex(where: { $0.id == captureID }) {
            recent[index].undone = true
        }
    }

    func acceptSuggestion(index: Int, api: APIClient, isConfigured: Bool = true) async {
        guard let response = lastResponse else { return }
        if !isConfigured || response.captureId.hasPrefix("showcase-") {
            guard response.suggestions.indices.contains(index) else { return }
            let sug = response.suggestions[index]
            var remaining = response.suggestions
            remaining.remove(at: index)
            let added = ExecutedAction(
                type: .listAdd,
                summary: "\(sug.items.count) item → \(sug.listName ?? "Costco")",
                confidence: 1.0,
                listId: "showcase-costco",
                listName: sug.listName ?? "Costco",
                items: sug.items
            )
            lastResponse = CaptureResponse(
                captureId: response.captureId,
                summary: "✓ \(added.summary)",
                actions: [added],
                suggestions: remaining
            )
            return
        }
        do {
            _ = try await accept(captureID: response.captureId, index: index, api: api)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    /// Accepts a "Did you mean…" suggestion and returns the updated capture.
    func accept(captureID: String, index: Int, api: APIClient) async throws -> CaptureResponse {
        isMutating = true
        defer { isMutating = false }
        let updated = try await api.acceptSuggestion(captureID: captureID, index: index)
        if lastResponse?.captureId == captureID { lastResponse = updated }
        await loadRecent(api: api)
        return updated
    }

    func dismissResult() {
        lastResponse = nil
        lastUndone = false
    }

    func loadRecent(api: APIClient, isConfigured: Bool = true) async {
        guard isConfigured else { return }
        isLoadingRecent = true
        defer { isLoadingRecent = false }
        do {
            recent = try await api.captures(limit: 20)
            recentError = nil
        } catch {
            if let message = userMessage(for: error) { recentError = message }
        }
    }

    private static func simulateLocalCapture(for text: String) -> CaptureResponse {
        let lower = text.lowercased()
        if lower.contains("costco") || lower.contains("walmart") || lower.contains("wish") {
            let target = lower.contains("walmart") ? "Walmart" : (lower.contains("wish") ? "Wish List" : "Costco")
            return CaptureResponse(
                captureId: "showcase-\(UUID().uuidString)",
                summary: "✓ Added to \(target)",
                actions: [
                    ExecutedAction(
                        type: .listAdd,
                        summary: "Added to \(target)",
                        confidence: 0.95,
                        listId: target == "Wish List" ? "showcase-wishlist" : "showcase-costco",
                        listName: target,
                        items: [text]
                    )
                ],
                suggestions: []
            )
        }
        return CaptureResponse(
            captureId: "showcase-\(UUID().uuidString)",
            summary: "✓ Note saved",
            actions: [
                ExecutedAction(
                    type: .note,
                    summary: "Note saved",
                    confidence: 0.95,
                    noteId: "showcase-note-1",
                    items: ["thought", "idea"]
                )
            ],
            suggestions: []
        )
    }
}
