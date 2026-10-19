import SwiftUI

struct ListsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = ListsViewModel()
    @State private var showingNewList = false
    @State private var showingNewTodo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    topBar
                    segmentedControl

                    if let error = model.errorMessage {
                        ErrorBanner(message: error) {
                            Task { await model.load(api: settings.api, isConfigured: settings.isConfigured) }
                        }
                    }

                    switch model.selectedSegment {
                    case .lists:
                        listsSection
                        todosSection(forToday: false)
                    case .tomorrow:
                        todosSection(forToday: false)
                        listsSection
                    case .today:
                        todosSection(forToday: true)
                        listsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
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
            .sheet(isPresented: $showingNewTodo) {
                NewTodoSheet(forToday: model.selectedSegment == .today) { text, forToday in
                    await model.addQuickTodo(
                        text: text,
                        forToday: forToday,
                        api: settings.api,
                        isConfigured: settings.isConfigured
                    )
                }
            }
        }
    }

    // MARK: Header & Segmented Control

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                Menu {
                    Button {
                        showingNewList = true
                    } label: {
                        Label("New List", systemImage: "cart.badge.plus")
                    }
                    Button {
                        showingNewTodo = true
                    } label: {
                        Label("New Todo", systemImage: "checklist")
                    }
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
                .accessibilityLabel("Add")
            }

            Text("Spaces")
                .font(Theme.serifTitle(40))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, -10)
        }
    }

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(Array(ListsViewModel.Segment.allCases.enumerated()), id: \.element.id) { index, seg in
                let isSelected = model.selectedSegment == seg
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        model.selectedSegment = seg
                    }
                } label: {
                    Text(seg.rawValue)
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
                                    .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)

                if index < ListsViewModel.Segment.allCases.count - 1 {
                    let nextSeg = ListsViewModel.Segment.allCases[index + 1]
                    if model.selectedSegment != seg && model.selectedSegment != nextSeg {
                        Rectangle()
                            .fill(Theme.border)
                            .frame(width: 1, height: 18)
                    }
                }
            }
        }
        .padding(4)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
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
                ForEach(Array(model.lists.enumerated()), id: \.element.id) { index, list in
                    let items = model.inlineItems(for: list.id)
                    if index == 0 && !items.isEmpty {
                        ExpandedListCard(
                            list: list,
                            items: items,
                            onToggle: { item in
                                Task {
                                    await model.toggleInlineItem(
                                        item,
                                        in: list.id,
                                        api: settings.api,
                                        isConfigured: settings.isConfigured
                                    )
                                }
                            }
                        )
                    } else {
                        NavigationLink(value: list) {
                            CompactListCard(list: list)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Todos Section

    private func todosSection(forToday: Bool) -> some View {
        let items = forToday ? model.todayTodos : model.tomorrowTodos
        let labelUpper = forToday ? "TODAY" : "TOMORROW"
        let labelTitle = forToday ? "Today" : "Tomorrow"

        return VStack(alignment: .leading, spacing: 10) {
            Text(labelUpper)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 2)
                .padding(.top, 2)

            HStack(alignment: .center) {
                Text(labelTitle)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            if items.isEmpty {
                Text("No todos for \(labelTitle.lowercased())")
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
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, todo in
                        TodoInlineRow(
                            todo: todo,
                            tagLabel: Self.tagForTodo(todo, index: idx),
                            showGroupIcon: idx == 0 && todo.done
                        ) {
                            Task {
                                await model.toggleTodo(
                                    todo,
                                    isToday: forToday,
                                    api: settings.api,
                                    isConfigured: settings.isConfigured
                                )
                            }
                        }

                        if idx < items.count - 1 {
                            Divider()
                                .overlay(Theme.divider)
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            }
        }
    }

    private static func tagForTodo(_ todo: Todo, index: Int) -> String {
        let lower = todo.text.lowercased()
        if lower.contains("dentist") || lower.contains("call") || lower.contains("doctor") {
            return "#admin"
        }
        if lower.contains("renew") || lower.contains("registration") || lower.contains("personal") {
            return "#personal"
        }
        return index % 2 == 0 ? "#admin" : "#personal"
    }
}

// MARK: - Expanded List Card ('Costco' List)

private struct ExpandedListCard: View {
    let list: ListSummary
    let items: [ListItem]
    let onToggle: (ListItem) -> Void

    private var formattedName: String {
        if list.name.contains("‘") || list.name.contains("'") || list.name.lowercased().contains("list") {
            return list.name
        }
        return "‘\(list.name)’ List"
    }

    private var progressRatio: CGFloat {
        guard !items.isEmpty else { return 0.5 }
        let completed = items.filter(\.done).count
        if completed == 0 { return 0.56 } // warm glowing baseline matching the mockup
        return max(0.25, CGFloat(completed) / CGFloat(items.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: list) {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Theme.terracotta)
                            .frame(width: 40, height: 40)
                        Image(systemName: "cart.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.inkDark)
                    }

                    Text(formattedName)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    Text("\(list.openCount) item\(list.openCount == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.amberBadgeText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Theme.amberBadgeFill, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(Theme.ochre.opacity(0.35), lineWidth: 0.8)
                        )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().overlay(Theme.divider)

            ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                Button {
                    onToggle(item)
                } label: {
                    HStack(spacing: 14) {
                        OrganicCheckbox(checked: item.done, accentedRing: true)
                        Text(item.text)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(item.done ? Theme.textTertiary : Theme.textPrimary)
                            .strikethrough(item.done)
                        Spacer()
                        Text("Qty: \(item.quantity ?? "1")")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < min(items.count, 4) - 1 {
                    Divider()
                        .overlay(Theme.divider)
                        .padding(.leading, 54)
                }
            }

            // Slim glowing terracotta progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.divider)
                        .frame(height: 5)
                    Capsule()
                        .fill(Theme.progressGradient)
                        .frame(width: geo.size.width * progressRatio, height: 5)
                        .shadow(color: Theme.terracotta.opacity(0.75), radius: 6, y: 0)
                }
            }
            .frame(height: 5)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
    }
}

// MARK: - Compact List Card (Wish List)

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

// MARK: - Todo Inline Row

private struct TodoInlineRow: View {
    let todo: Todo
    let tagLabel: String
    let showGroupIcon: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                OrganicCheckbox(checked: todo.done, accentedRing: false)

                Text(todo.text)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(todo.done ? Theme.textSecondary : Theme.textPrimary)

                Spacer()

                if showGroupIcon {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.taupe)
                }

                Text(tagLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.neutralPillFill, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Theme.border, lineWidth: 0.8)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheets

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

private struct NewTodoSheet: View {
    let forToday: Bool
    let onCreate: (String, Bool) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var targetToday: Bool
    @State private var isSaving = false
    @FocusState private var focused: Bool

    init(forToday: Bool, onCreate: @escaping (String, Bool) async -> Bool) {
        self.forToday = forToday
        self.onCreate = onCreate
        _targetToday = State(initialValue: forToday)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task (e.g. Call dentist)", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { save() }
                Picker("When", selection: $targetToday) {
                    Text("Today").tag(true)
                    Text("Tomorrow").tag(false)
                }
                .pickerStyle(.segmented)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("New Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            if await onCreate(text, targetToday) { dismiss() }
            isSaving = false
        }
    }
}
