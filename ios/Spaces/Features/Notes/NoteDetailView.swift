import SwiftUI

/// View, edit (PATCH) and delete a single note.
struct NoteDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let noteID: String
    @State private var note: Note?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var errorMessage: String?

    @State private var isEditing = false
    @State private var isSaving = false
    @State private var draftTitle = ""
    @State private var draftText = ""
    @State private var draftTags = ""
    @State private var confirmDelete = false

    init(note: Note) {
        self.noteID = note.id
        _note = State(initialValue: note)
    }

    init(noteID: String) {
        self.noteID = noteID
        if let sample = ShowcaseData.notes.first(where: { $0.id == noteID }) {
            _note = State(initialValue: sample)
        }
    }

    var body: some View {
        Group {
            if isEditing {
                editor
            } else if let note {
                reader(note)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn’t load note", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else {
                ProgressView()
                    .tint(Theme.apricot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(isEditing ? "Edit Note" : "Note")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar { toolbar }
        .task { await load() }
        .errorAlert($errorMessage)
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) { Task { await delete() } }
        } message: {
            Text("This can’t be undone.")
        }
    }

    // MARK: Reader

    private func reader(_ note: Note) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(note.displayTitle)
                    .font(Theme.serifTitle(30))
                    .foregroundStyle(Theme.textPrimary)

                if !note.tags.isEmpty {
                    TagChips(tags: note.tags, style: .warmSolid)
                }

                Text(note.text)
                    .font(.system(size: 17.5, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.92))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Label(note.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    if note.updatedAt.timeIntervalSince(note.createdAt) > 1 {
                        Label("Edited \(note.updatedAt.formatted(.relative(presentation: .named)))",
                              systemImage: "pencil")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .refreshable { await load() }
    }

    // MARK: Editor

    private var editor: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $draftTitle)
            }
            Section("Text") {
                TextEditor(text: $draftText)
                    .frame(minHeight: 220)
            }
            Section {
                TextField("garage, idea", text: $draftTags)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Tags")
            } footer: {
                Text("Separate tags with commas.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isEditing = false }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        } else if note != nil {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
                Button("Edit") { beginEditing() }
            }
        }
    }

    // MARK: Actions

    private func beginEditing() {
        guard let note else { return }
        draftTitle = note.title ?? ""
        draftText = note.text
        draftTags = note.tags.joined(separator: ", ")
        isEditing = true
    }

    static func parseTags(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private func load() async {
        guard settings.isConfigured, !noteID.hasPrefix("showcase-") else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            note = try await settings.api.note(id: noteID)
            loadError = nil
        } catch {
            guard let message = userMessage(for: error) else { return }
            if note == nil { loadError = message } else { errorMessage = message }
        }
    }

    private func save() async {
        guard let current = note else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = Self.parseTags(draftTags)
        if !settings.isConfigured || current.id.hasPrefix("showcase-") {
            self.note = Note(
                id: current.id,
                text: text,
                title: title.isEmpty ? nil : title,
                tags: tags,
                createdAt: current.createdAt,
                updatedAt: Date()
            )
            isEditing = false
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            self.note = try await settings.api.updateNote(
                id: current.id,
                text: text != current.text ? text : nil,
                title: title != (current.title ?? "") ? title : nil,
                tags: tags != current.tags ? tags : nil
            )
            isEditing = false
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func delete() async {
        if !settings.isConfigured || noteID.hasPrefix("showcase-") {
            dismiss()
            return
        }
        do {
            try await settings.api.deleteNote(id: noteID)
            dismiss()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
