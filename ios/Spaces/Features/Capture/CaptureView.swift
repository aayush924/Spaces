import SwiftUI
import UIKit

struct CaptureView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = CaptureViewModel()
    @State private var speech = SpeechRecognizer()
    /// Editor text that existed before dictation started; the live transcript is appended to it.
    @State private var textBeforeDictation = ""
    @State private var applyTranscript = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        editor

                        if let message = speech.errorMessage {
                            speechError(message)
                        }

                        if let response = model.lastResponse {
                            CaptureResultCard(
                                response: response,
                                undone: model.lastUndone,
                                busy: model.isMutating,
                                onUndo: {
                                    Task {
                                        await model.undoLast(api: settings.api, isConfigured: settings.isConfigured)
                                    }
                                },
                                onAccept: { index in
                                    Task {
                                        await model.acceptSuggestion(
                                            index: index,
                                            api: settings.api,
                                            isConfigured: settings.isConfigured
                                        )
                                    }
                                },
                                onDismiss: { withAnimation { model.dismissResult() } }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if !model.recent.isEmpty {
                            recentSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 195)
                    .animation(.snappy, value: model.lastResponse)
                }
                .scrollDismissesKeyboard(.interactively)

                floatingMicBar
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.loadRecent(api: settings.api, isConfigured: settings.isConfigured)
            }
            .task(id: settings.baseURL + settings.token) {
                await model.loadRecent(api: settings.api, isConfigured: settings.isConfigured)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Send") { Task { await send() } }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.apricot)
                    Button("Done") { editorFocused = false }
                }
            }
            .errorAlert($model.errorMessage)
            .onChange(of: speech.transcript) { _, newValue in
                guard applyTranscript, !newValue.isEmpty else { return }
                model.text = textBeforeDictation.isEmpty ? newValue : textBeforeDictation + " " + newValue
            }
            .onDisappear { speech.stop() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("What's on your mind?")
                .font(Theme.serifTitle(32))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if editorFocused && model.canSend {
                Button {
                    Task { await send() }
                } label: {
                    HStack(spacing: 5) {
                        if model.isSending {
                            ProgressView().tint(Theme.inkDark).controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text("Send")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.inkDark)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.apricot, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: Editor

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.text)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.apricot)
                .lineSpacing(4)
                .frame(minHeight: 150)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            if model.text.isEmpty {
                Text(speech.isRecording ? "Listening…" : "Type here or press mic to speak")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 19)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    speech.isRecording ? Theme.terracotta : Theme.border,
                    lineWidth: speech.isRecording ? 1.8 : 1
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }

    // MARK: Floating Mic Button

    private var floatingMicBar: some View {
        HStack {
            Spacer()
            Button {
                Task { await toggleDictation() }
            } label: {
                ZStack {
                    Circle()
                        .fill(speech.isRecording ? Theme.terracotta : Theme.cardElevated)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    speech.isRecording ? Theme.apricot : Theme.border,
                                    lineWidth: 1.2
                                )
                        )
                        .shadow(
                            color: speech.isRecording ? Theme.terracotta.opacity(0.5) : .black.opacity(0.45),
                            radius: 12,
                            y: 4
                        )
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .symbolEffect(.pulse, isActive: speech.isRecording)
                }
            }
            .buttonStyle(.plain)
            .disabled(speech.status == .requestingPermission)
            .accessibilityLabel(speech.isRecording ? "Stop dictation" : "Start dictation")
            Spacer()
        }
        .padding(.bottom, 108)
    }

    private func speechError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mic.slash.fill").foregroundStyle(Theme.terracotta)
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.callout).foregroundStyle(Theme.textPrimary)
                if speech.permissionDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.apricot)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.terracotta.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: Recent

    @ViewBuilder
    private var recentSection: some View {
        HStack {
            Text("RECENT")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            if model.isLoadingRecent { ProgressView().controlSize(.small).tint(Theme.apricot) }
        }
        .padding(.top, 8)

        if let error = model.recentError {
            ErrorBanner(message: error) {
                Task { await model.loadRecent(api: settings.api, isConfigured: settings.isConfigured) }
            }
        }

        LazyVStack(spacing: 10) {
            ForEach(model.recent) { capture in
                NavigationLink {
                    CaptureDetailView(capture: capture, model: model)
                } label: {
                    RecentCaptureRow(capture: capture)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Actions

    private func toggleDictation() async {
        if speech.isRecording {
            speech.stop()
        } else {
            textBeforeDictation = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
            applyTranscript = true
            editorFocused = false
            await speech.start()
        }
    }

    private func send() async {
        if speech.isRecording { speech.stop() }
        applyTranscript = false
        editorFocused = false
        await model.send(api: settings.api, isConfigured: settings.isConfigured)
    }
}

// MARK: - Result card (Glowing AI card + Dashed Suggestions box)

struct CaptureResultCard: View {
    let response: CaptureResponse
    let undone: Bool
    let busy: Bool
    var onUndo: () -> Void
    var onAccept: (Int) -> Void
    var onDismiss: (() -> Void)?

    private var primaryTitle: String {
        if undone { return "Undone" }
        if let first = response.actions.first { return first.title }
        return response.summary.isEmpty ? "Note saved" : response.summary
    }

    private var tagsToDisplay: [String] {
        if let first = response.actions.first, !first.items.isEmpty {
            return first.items
        }
        return ["garage", "idea"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Glowing AI Result Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("A\\")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.apricot)
                        .tracking(-0.5)

                    Spacer()

                    if !undone {
                        Button(action: onUndo) {
                            Text("Undo")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Theme.neutralPillFill, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Theme.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    } else if let onDismiss {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: undone ? "arrow.uturn.backward" : "checkmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(primaryTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .strikethrough(undone)
                }

                if !tagsToDisplay.isEmpty {
                    TagChips(tags: tagsToDisplay, style: .warmSolid)
                        .opacity(undone ? 0.5 : 1)
                }

                if response.actions.count > 1 {
                    Divider().overlay(Theme.divider)
                    ForEach(Array(response.actions.dropFirst().enumerated()), id: \.offset) { _, action in
                        ActionRowLink(action: action, undone: undone)
                    }
                }
            }
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.glowingBorderGradient, lineWidth: 1.5)
            )
            .shadow(color: Theme.apricot.opacity(0.24), radius: 14, y: 2)

            // Dashed Suggestions Card
            if !response.suggestions.isEmpty && !undone {
                ForEach(Array(response.suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button {
                        onAccept(index)
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            (
                                Text("Suggestions: ")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                + Text(Self.cleanSuggestionLabel(suggestion.label))
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(Theme.textSecondary)
                            )
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)
                        .background(Theme.dock, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    Theme.border,
                                    style: StrokeStyle(lineWidth: 1.1, dash: [5, 4])
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
    }

    private static func cleanSuggestionLabel(_ raw: String) -> String {
        if raw.lowercased().hasPrefix("did you mean") {
            return raw
        }
        return "Did you mean \(raw.lowercased())?"
    }
}

/// One executed action; tappable when it points at a note or list.
struct ActionRowLink: View {
    let action: ExecutedAction
    let undone: Bool

    var body: some View {
        if !undone, action.type == .note, let noteID = action.noteId {
            NavigationLink { NoteDetailView(noteID: noteID) } label: { row(chevron: true) }
                .buttonStyle(.plain)
        } else if !undone, let listID = action.listId, action.type == .listAdd || action.type == .listItemRemove {
            NavigationLink { ListDetailView(listID: listID, name: action.listName ?? "List") } label: { row(chevron: true) }
                .buttonStyle(.plain)
        } else {
            row(chevron: false)
        }
    }

    private func row(chevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: action.type.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(action.type.tint)
                .frame(width: 34, height: 34)
                .background(action.type.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if action.isLowConfidence {
                        Text("unsure")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.ochre.opacity(0.25), in: Capsule())
                            .foregroundStyle(Theme.ochre)
                    }
                }
                if !action.items.isEmpty {
                    Text(action.items.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                } else if !action.summary.isEmpty, action.summary != action.title {
                    Text(action.summary)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .strikethrough(undone)
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 10)
            }
        }
        .contentShape(Rectangle())
        .opacity(undone ? 0.5 : 1)
    }
}

// MARK: - Recent capture row & detail

struct RecentCaptureRow: View {
    let capture: Capture

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: capture.actions.first?.type.symbolName ?? "text.bubble")
                .foregroundStyle(capture.undone ? Theme.textTertiary : (capture.actions.first?.type.tint ?? Theme.apricot))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(capture.rawText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .strikethrough(capture.undone)
                HStack(spacing: 6) {
                    Text(capture.undone ? "Undone" : capture.summary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(capture.createdAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 6)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

struct CaptureDetailView: View {
    @Environment(AppSettings.self) private var settings
    let model: CaptureViewModel
    @State private var capture: Capture
    @State private var response: CaptureResponse
    @State private var errorMessage: String?

    init(capture: Capture, model: CaptureViewModel) {
        self.model = model
        _capture = State(initialValue: capture)
        _response = State(initialValue: capture.asResponse)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(capture.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Text(capture.rawText)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )

                CaptureResultCard(
                    response: response,
                    undone: capture.undone,
                    busy: model.isMutating,
                    onUndo: {
                        Task {
                            do {
                                try await model.undo(captureID: capture.id, api: settings.api)
                                capture.undone = true
                            } catch {
                                errorMessage = userMessage(for: error)
                            }
                        }
                    },
                    onAccept: { index in
                        Task {
                            do {
                                response = try await model.accept(captureID: capture.id, index: index, api: settings.api)
                            } catch {
                                errorMessage = userMessage(for: error)
                            }
                        }
                    }
                )
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert($errorMessage)
    }
}
