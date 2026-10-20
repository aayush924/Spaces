import SwiftUI

struct SearchView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = SearchViewModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.mode == .search ? "Search" : "Ask")
                        .font(Theme.serifTitle(42))
                        .foregroundStyle(Theme.textPrimary)

                    modeSegment

                    searchBar

                    if let error = model.errorMessage {
                        ErrorBanner(message: error) { Task { await rerun() } }
                    }

                    if model.isLoading && model.results.isEmpty && model.answer == nil {
                        HStack {
                            Spacer()
                            ProgressView(model.mode == .ask ? "Thinking…" : "Searching…")
                                .tint(Theme.apricot)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                        }
                        .padding(.vertical, 36)
                    }

                    switch model.mode {
                    case .search:
                        searchContent
                    case .ask:
                        askContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 125)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task(id: "\(model.mode.rawValue)|\(model.query)") {
                await model.debouncedSearch(api: settings.api, isConfigured: settings.isConfigured)
            }
            .refreshable { await rerun() }
        }
    }

    private var modeSegment: some View {
        HStack(spacing: 0) {
            ForEach(SearchViewModel.Mode.allCases) { mode in
                let isSelected = model.mode == mode
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        model.mode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.segmentActive)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: model.mode == .search ? "magnifyingglass" : "sparkles")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.apricot)

            TextField(
                model.mode == .search
                    ? "Search by concept or phrase…"
                    : "Ask your journal a question…",
                text: $model.query
            )
            .font(.system(size: 17))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.apricot)
            .focused($searchFocused)
            .submitLabel(.search)
            .onSubmit {
                Task { await rerun() }
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

    private func rerun() async {
        switch model.mode {
        case .search:
            if !model.trimmedQuery.isEmpty {
                await model.search(model.trimmedQuery, api: settings.api, isConfigured: settings.isConfigured)
            }
        case .ask:
            await model.ask(api: settings.api, isConfigured: settings.isConfigured)
        }
    }

    // MARK: Search Results

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
        } else if model.hasSearched && model.results.isEmpty && !model.isLoading {
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
                ForEach(model.results) { result in
                    NavigationLink {
                        NoteDetailView(note: result.note)
                    } label: {
                        NoteCardView(note: result.note)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Ask

    @ViewBuilder
    private var askContent: some View {
        if let answer = model.answer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.apricot)
                    Text("Synthesis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.apricot)
                    Spacer()
                }
                if let question = model.askedQuestion {
                    Text(question)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(answer.answer)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.glowingBorderGradient, lineWidth: 1.5)
            )
            .shadow(color: Theme.apricot.opacity(0.22), radius: 12, y: 2)

            if !answer.citations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("SOURCES")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 2)

                    ForEach(answer.citations) { note in
                        NavigationLink {
                            NoteDetailView(note: note)
                        } label: {
                            NoteCardView(note: note)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if !model.isLoading {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ask anything across your thoughts")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Try “What ideas have I had about the garage?” and press Search.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                if !model.trimmedQuery.isEmpty {
                    Button {
                        Task { await model.ask(api: settings.api, isConfigured: settings.isConfigured) }
                    } label: {
                        Label("Ask “\(model.trimmedQuery)”", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.inkDark)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.apricot, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
        }
    }
}

/// Compact note row retained for compatibility.
struct NoteRow: View {
    let note: Note
    let match: String?

    var body: some View {
        NoteCardView(note: note)
    }
}
