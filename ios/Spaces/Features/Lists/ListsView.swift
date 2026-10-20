import SwiftUI

struct ListsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = ListsViewModel()
    @State private var showingNewList = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    topBar

                    if let error = model.errorMessage {
                        ErrorBanner(message: error) {
                            Task { await model.load(api: settings.api, isConfigured: settings.isConfigured) }
                        }
                    }

                    listsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 125)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ListSummary.self) { list in
                ListDetailView(list: list)
            }
            .refreshable {
                await model.load(api: settings.api, isConfigured: settings.isConfigured)
            }
            .task(id: settings.baseURL + settings.token) {
                await model.load(api: settings.api, isConfigured: settings.isConfigured)
            }
            .sheet(isPresented: $showingNewList) {
                NewListSheet { name, kind in
                    await model.create(
                        name: name,
                        kind: kind,
                        api: settings.api,
                        isConfigured: settings.isConfigured
                    )
                }
            }
        }
    }

    // MARK: Header

    private var topBar: some View {
        HStack(alignment: .center) {
            Text("Lists")
                .font(Theme.serifTitle(42))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Button {
                showingNewList = true
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.apricotSoft, Theme.apricot],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                        )
                        .shadow(color: Theme.apricot.opacity(0.35), radius: 8, y: 2)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.inkDark)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New List")
        }
    }

    // MARK: Lists Section

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LISTS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 2)

            if model.lists.isEmpty {
                Text("No lists yet")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
            } else {
                ForEach(model.lists) { list in
                    SwipeToDeleteContainer {
                        Task {
                            await model.delete(
                                list,
                                api: settings.api,
                                isConfigured: settings.isConfigured
                            )
                        }
                    } content: {
                        NavigationLink(value: list) {
                            CompactListCard(list: list)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Swipe To Delete Container

private struct SwipeToDeleteContainer<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offsetX: CGFloat = 0
    @State private var isOpen = false
    @State private var isDraggingHorizontally = false

    private let revealWidth: CGFloat = 74

    var body: some View {
        ZStack(alignment: .trailing) {
            if offsetX < -2 || isOpen {
                Button(role: .destructive) {
                    withAnimation(.snappy(duration: 0.25)) {
                        offsetX = 0
                        isOpen = false
                        onDelete()
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Theme.terracotta)
                        Image(systemName: "trash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.inkDark)
                    }
                    .frame(width: 62)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete list")
            }

            content()
                .disabled(isOpen || isDraggingHorizontally)
                .overlay {
                    if isOpen {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    offsetX = 0
                                    isOpen = false
                                }
                            }
                    }
                }
                .offset(x: offsetX)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16, coordinateSpace: .local)
                        .onChanged { value in
                            if !isDraggingHorizontally {
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                isDraggingHorizontally = true
                            }
                            let base: CGFloat = isOpen ? -revealWidth : 0
                            let proposed = base + value.translation.width
                            offsetX = min(0, max(-revealWidth - 18, proposed))
                        }
                        .onEnded { value in
                            defer { isDraggingHorizontally = false }
                            guard isDraggingHorizontally || isOpen else { return }
                            let base: CGFloat = isOpen ? -revealWidth : 0
                            let projected = base + value.predictedEndTranslation.width
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                if projected < -revealWidth * 0.45 || offsetX < -revealWidth * 0.45 {
                                    offsetX = -revealWidth
                                    isOpen = true
                                } else {
                                    offsetX = 0
                                    isOpen = false
                                }
                            }
                        }
                )
        }
    }
}

// MARK: - Compact List Card

private struct CompactListCard: View {
    let list: ListSummary

    private var isWishList: Bool {
        list.kind == "wishlist" || list.name.lowercased().contains("wish")
    }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isWishList ? Theme.taupe : Theme.terracotta)
                    .frame(width: 40, height: 40)
                Image(systemName: isWishList ? "star.fill" : list.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.inkDark)
            }

            Text(list.name)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Text("\(list.openCount) item\(list.openCount == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Theme.neutralPillFill, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Theme.border, lineWidth: 0.8)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

// MARK: - New List Sheet

private struct NewListSheet: View {
    let onCreate: (String, ListKind) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: ListKind = .shopping
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Trader Joe’s)", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { save() }
                Picker("Kind", selection: $kind) {
                    ForEach(ListKind.allCases) { Text($0.label).tag($0) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("New list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { nameFocused = true }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            if await onCreate(name, kind) { dismiss() }
            isSaving = false
        }
    }
}
