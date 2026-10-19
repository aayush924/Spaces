import SwiftUI
import Observation

@MainActor
@Observable
final class NotesListViewModel {
    private(set) var notes: [Note] = []
    private(set) var isLoading = false
    private(set) var hasLoadedLive = false
    var filterText = ""
    var showingFilter = false
    var errorMessage: String?

    var displayedNotes: [Note] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return notes }
        return notes.filter {
            $0.displayTitle.lowercased().contains(q)
                || $0.text.lowercased().contains(q)
                || $0.tags.contains(where: { $0.lowercased().contains(q) })
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if model.showingFilter {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Theme.textTertiary)
                            TextField("Filter notes or #tags…", text: $model.filterText)
                                .foregroundStyle(Theme.textPrimary)
                                .tint(Theme.apricot)
                            if !model.filterText.isEmpty {
                                Button {
                                    model.filterText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let error = model.errorMessage {
                        ErrorBanner(message: error) {
                            Task { await model.load(api: settings.api, isConfigured: settings.isConfigured) }
                        }
                    }

                    LazyVStack(spacing: 16) {
                        ForEach(model.displayedNotes) { note in
                            NavigationLink {
                                NoteDetailView(note: note)
                            } label: {
                                NoteCardView(note: note)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.load(api: settings.api, isConfigured: settings.isConfigured)
            }
            .task(id: settings.baseURL + settings.token) {
                await model.load(api: settings.api, isConfigured: settings.isConfigured)
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
                    model.showingFilter.toggle()
                    if !model.showingFilter { model.filterText = "" }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(model.showingFilter ? Theme.apricot : Theme.textSecondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter notes")
        }
        .padding(.bottom, 4)
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
