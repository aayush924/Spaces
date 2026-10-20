import SwiftUI

struct TodosView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = TodosViewModel()
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
                    case .today:
                        todosSection(forToday: true)
                    case .later:
                        todosSection(forToday: false)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 125)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.load(api: settings.api, isConfigured: settings.isConfigured)
            }
            .task(id: settings.baseURL + settings.token) {
                await model.load(api: settings.api, isConfigured: settings.isConfigured)
            }
            .sheet(isPresented: $showingNewTodo) {
                NewTodoSheet(forToday: model.selectedSegment == .today) { text, dueDate in
                    await model.addTodo(
                        text: text,
                        dueDate: dueDate,
                        api: settings.api,
                        isConfigured: settings.isConfigured
                    )
                }
            }
        }
    }

    // MARK: Header & Segmented Control

    private var topBar: some View {
        HStack(alignment: .center) {
            Text("Todos")
                .font(Theme.serifTitle(42))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Button {
                showingNewTodo = true
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
            .accessibilityLabel("New Todo")
        }
    }

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(Array(TodosViewModel.Segment.allCases.enumerated()), id: \.element.id) { index, seg in
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

                if index < TodosViewModel.Segment.allCases.count - 1 {
                    let nextSeg = TodosViewModel.Segment.allCases[index + 1]
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

    // MARK: Todos Section

    private func todosSection(forToday: Bool) -> some View {
        let items = forToday ? model.todayTodos : model.laterTodos
        let labelUpper = forToday ? "TODAY" : "LATER"
        let labelTitle = forToday ? "Today" : "Later"

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
                            tagLabel: forToday ? Self.tagForTodo(todo, index: idx) : LocalDate.display(todo.dueDate),
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
                    .strikethrough(todo.done, color: Theme.textTertiary)

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

// MARK: - New Todo Sheet

private struct NewTodoSheet: View {
    let forToday: Bool
    let onCreate: (String, String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var targetToday: Bool
    @State private var laterDate: Date
    @State private var isSaving = false
    @FocusState private var focused: Bool

    init(forToday: Bool, onCreate: @escaping (String, String) async -> Bool) {
        self.forToday = forToday
        self.onCreate = onCreate
        _targetToday = State(initialValue: forToday)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        _laterDate = State(initialValue: tomorrow)
    }

    private var minimumLaterDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
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
                    Text("Later").tag(false)
                }
                .pickerStyle(.segmented)

                if !targetToday {
                    DatePicker(
                        "Date",
                        selection: $laterDate,
                        in: minimumLaterDate...,
                        displayedComponents: .date
                    )
                    .tint(Theme.apricot)
                }
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
        let due = targetToday ? LocalDate.today() : LocalDate.string(from: laterDate)
        Task {
            if await onCreate(text, due) { dismiss() }
            isSaving = false
        }
    }
}
