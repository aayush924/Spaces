import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case search = "Search"
        case ask = "Ask"
        var id: String { rawValue }
    }

    private static let recentSearchesKey = "recentSearches"
    private static let maxRecentSearches = 5

    var query = ""
    var mode: Mode = .search
    private(set) var results: [SearchResult] = []
    private(set) var recentSearches: [String]
    private(set) var answer: AskResponse?
    private(set) var askedQuestion: String?
    private(set) var isLoading = false
    private(set) var hasSearched = false
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.recentSearchesKey) ?? []
        self.recentSearches = Array(stored.prefix(Self.maxRecentSearches))
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func recordRecentSearch(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = recentSearches
        // If the user continued typing from the most recent debounced query, replace the prefix.
        if let first = updated.first,
           trimmed.lowercased().hasPrefix(first.lowercased()) || first.lowercased().hasPrefix(trimmed.lowercased()),
           abs(trimmed.count - first.count) <= 6 {
            updated.removeFirst()
        }
        updated.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        updated.insert(trimmed, at: 0)
        if updated.count > Self.maxRecentSearches {
            updated = Array(updated.prefix(Self.maxRecentSearches))
        }
        recentSearches = updated
        defaults.set(updated, forKey: Self.recentSearchesKey)
    }

    func removeRecentSearch(_ item: String) {
        recentSearches.removeAll { $0 == item }
        defaults.set(recentSearches, forKey: Self.recentSearchesKey)
    }

    /// Debounced search, intended to be driven from `.task(id:)` so that each
    /// keystroke cancels the previous in-flight wait/request.
    func debouncedSearch(api: APIClient, isConfigured: Bool = true) async {
        guard mode == .search else { return }
        let q = trimmedQuery
        guard !q.isEmpty else {
            results = []
            hasSearched = false
            errorMessage = nil
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }
        await search(q, api: api, isConfigured: isConfigured)
    }

    func search(_ q: String, api: APIClient, isConfigured: Bool = true) async {
        if !isConfigured {
            let lower = q.lowercased()
            let matched = ShowcaseData.notes.filter {
                $0.displayTitle.lowercased().contains(lower)
                    || $0.text.lowercased().contains(lower)
                    || $0.tags.contains(where: { $0.lowercased().contains(lower) })
                    || (lower.contains("bike") && $0.tags.contains("garage"))
            }
            results = (matched.isEmpty ? ShowcaseData.notes : matched).map {
                SearchResult(note: $0, score: 0.92, match: "semantic")
            }
            hasSearched = true
            errorMessage = nil
            recordRecentSearch(q)
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await api.search(q, limit: 20)
            guard !Task.isCancelled, q == trimmedQuery else { return }
            results = found
            hasSearched = true
            errorMessage = nil
            recordRecentSearch(q)
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func ask(api: APIClient, isConfigured: Bool = true) async {
        let q = trimmedQuery
        guard !q.isEmpty, !isLoading else { return }
        if !isConfigured {
            askedQuestion = q
            answer = AskResponse(
                answer: "You noted an idea about installing a pegboard wall in the garage so bikes can hang vertically [1].",
                citations: [ShowcaseData.notes[0]]
            )
            errorMessage = nil
            recordRecentSearch(q)
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            answer = try await api.ask(q)
            askedQuestion = q
            errorMessage = nil
            recordRecentSearch(q)
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }
}
