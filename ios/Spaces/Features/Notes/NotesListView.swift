import SwiftUI
import Observation

@MainActor
@Observable
final class NotesListViewModel {
    private static let recentSearchesKey = "recentSearches"
    private static let maxRecentSearches = 5
    private static let maxSearchResults = 15

    private(set) var notes: [Note] = []
    private(set) var searchResults: [Note] = []
    private(set) var recentSearches: [String]
    private(set) var isLoading = false
    private(set) var isSearching = false
    private(set) var hasSearched = false
    private(set) var hasLoadedLive = false
    var query = ""
    var showingSearch = false
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.recentSearchesKey) ?? []
        self.recentSearches = Array(stored.prefix(Self.maxRecentSearches))
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isExactMatch(_ note: Note, for lowerQuery: String) -> Bool {
        guard !lowerQuery.isEmpty else { return false }
        return note.displayTitle.lowercased().contains(lowerQuery)
            || note.text.lowercased().contains(lowerQuery)
            || note.tags.contains(where: { $0.lowercased().contains(lowerQuery) })
    }

    func recordRecentSearch(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = recentSearches
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

    func debouncedSearch(api: APIClient, isConfigured: Bool) async {
        guard showingSearch else { return }
        let q = trimmedQuery
        guard !q.isEmpty else {
            searchResults = []
            hasSearched = false
            isSearching = false
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

    func search(_ q: String, api: APIClient, isConfigured: Bool) async {
        let lower = q.lowercased()
        let localExact = notes.filter { isExactMatch($0, for: lower) }

        if !isConfigured {
            let showcaseSource = notes.isEmpty ? ShowcaseData.notes : notes
            let exact = showcaseSource.filter { isExactMatch($0, for: lower) }
            let exactIDs = Set(exact.map(\.id))
            let related = showcaseSource.filter {
                !exactIDs.contains($0.id) && (lower.contains("bike") && $0.tags.contains("garage"))
            }
            searchResults = Array((exact + related).prefix(Self.maxSearchResults))
            hasSearched = true
            errorMessage = nil
            recordRecentSearch(q)
            return
        }

        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await api.search(q, limit: Self.maxSearchResults)
            guard !Task.isCancelled, q == trimmedQuery else { return }
            let apiNotes = found.map(\.note)

            // Combine exact matches first, then semantic/search findings, deduplicated and capped at 15.
            var exactMatches: [Note] = []
            var relatedMatches: [Note] = []
            var seenIDs = Set<String>()

            for note in apiNotes + localExact {
                guard !seenIDs.contains(note.id) else { continue }
                if isExactMatch(note, for: lower) {
                    seenIDs.insert(note.id)
                    exactMatches.append(note)
                }
            }
            for note in apiNotes {
                guard !seenIDs.contains(note.id) else { continue }
                seenIDs.insert(note.id)
                relatedMatches.append(note)
            }

            searchResults = Array((exactMatches + relatedMatches).prefix(Self.maxSearchResults))
            hasSearched = true
            errorMessage = nil
            recordRecentSearch(q)
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func load(api: APIClient, isConfigured: Bool) async {
        guard isConfigured else {
            notes = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            notes = try await api.notes(limit: 50)
            hasLoadedLive = true
            errorMessage = nil
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func create(title: String?, text: String, tags: [String], api: APIClient, isConfigured: Bool) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if !isConfigured {
            let now = Date()
            let local = Note(
                id: UUID().uuidString,
                text: trimmed,
                title: title?.isEmpty == false ? title : nil,
                tags: tags,
                createdAt: now,
                updatedAt: now
            )
            notes.insert(local, at: 0)
            return true
        }
        do {
            let created = try await api.createNote(text: trimmed, title: title, tags: tags)
            notes.insert(created, at: 0)
            return true
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
            return false
        }
    }
}

struct NotesListView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = NotesListViewModel()
    @State private var showingNewNote = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if model.showingSearch {
                        searchBar
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let error = model.errorMessage {
                        ErrorBanner(message: error) {
                            Task {
                                if model.showingSearch && !model.trimmedQuery.isEmpty {
                                    await model.search(
                                        model.trimmedQuery,
                                        api: settings.api,
                                        isConfigured: settings.isConfigured
                                    )
                                } else {
                                    await model.load(api: settings.api, isConfigured: settings.isConfigured)
                                }
                            }
                        }
                    }

                    if model.showingSearch {
                        searchContent
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(model.notes) { note in
                                NavigationLink {
                                    NoteDetailView(note: note)
                                } label: {
                                    NoteCardView(note: note)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                if model.showingSearch && !model.trimmedQuery.isEmpty {
                    await model.search(
                        model.trimmedQuery,
                        api: settings.api,
                        isConfigured: settings.isConfigured
                    )
                } else {
                    await model.load(api: settings.api, isConfigured: settings.isConfigured)
                }
            }
            .task(id: settings.baseURL + settings.token) {
                await model.load(api: settings.api, isConfigured: settings.isConfigured)
            }
            .task(id: "\(model.showingSearch)|\(model.query)") {
                await model.debouncedSearch(api: settings.api, isConfigured: settings.isConfigured)
            }
            .sheet(isPresented: $showingNewNote) {
                NewNoteSheet { title, text, tags in
                    await model.create(
                        title: title,
                        text: text,
                        tags: tags,
                        api: settings.api,
                        isConfigured: settings.isConfigured
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Notes")
                .font(Theme.serifTitle(42))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                withAnimation(.snappy) {
                    model.showingSearch.toggle()
                    if model.showingSearch {
                        searchFocused = true
                    } else {
                        model.query = ""
                        searchFocused = false
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(model.showingSearch ? Theme.apricot : Theme.textSecondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search notes")
        }
        .padding(.bottom, 4)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.apricot)

            TextField("Search by concept or phrase…", text: $model.query)
                .font(.system(size: 17))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.apricot)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    let q = model.trimmedQuery
                    guard !q.isEmpty else { return }
                    Task {
                        await model.search(q, api: settings.api, isConfigured: settings.isConfigured)
                    }
                }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var searchContent: some View {
        if model.trimmedQuery.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("RECENT SEARCHES")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.leading, 2)

                if model.recentSearches.isEmpty {
                    Text("No recent searches yet")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 2)
                        .padding(.top, 4)
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.recentSearches, id: \.self) { recent in
                            HStack(spacing: 12) {
                                Button {
                                    model.query = recent
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Theme.textTertiary)
                                        Text(recent)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(Theme.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        model.removeRecentSearch(recent)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.textTertiary)
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Theme.border, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        } else if model.isSearching && model.searchResults.isEmpty {
            HStack {
                Spacer()
                ProgressView("Searching…")
                    .tint(Theme.apricot)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.vertical, 36)
        } else if model.hasSearched && model.searchResults.isEmpty && !model.isSearching {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.textTertiary)
                Text("No matching notes for “\(model.trimmedQuery)”")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(model.searchResults) { note in
                    NavigationLink {
                        NoteDetailView(note: note)
                    } label: {
                        NoteCardView(note: note)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NoteCardView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(note.displayTitle)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            if !note.tags.isEmpty {
                TagChips(tags: note.tags, style: .warmSolid)
            }

            Text(note.text)
                .font(.system(size: 16.5, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)

            HStack {
                Spacer()
                Text(Self.timestampLabel(for: note.createdAt))
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }

    static func timestampLabel(for date: Date, now: Date = Date()) -> String {
        let hours = now.timeIntervalSince(date) / 3600
        if hours < 1 {
            let mins = max(1, Int(now.timeIntervalSince(date) / 60))
            return "\(mins) min ago"
        } else if hours < 24 {
            let h = max(1, Int(round(hours)))
            return "\(h) hour\(h == 1 ? "" : "s") ago"
        } else if hours < 48 {
            return "Yesterday"
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

private struct NewNoteSheet: View {
    let onCreate: (String?, String, [String]) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var tagsText = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Optional title", text: $title)
                }
                Section("Thought") {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                }
                Section("Tags (comma-separated)") {
                    TextField("garage, idea", text: $tagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !isSaving else { return }
                        isSaving = true
                        Task {
                            let tags = NoteDetailView.parseTags(tagsText)
                            if await onCreate(title, text, tags) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
