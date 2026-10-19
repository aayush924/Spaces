import SwiftUI

struct TodosView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = TodosViewModel()
    @FocusState private var addFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Todos")
                            .font(Theme.serifTitle(34))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.top, 4)

                        Picker("Day", selection: $model.day) {
                            ForEach(TodosViewModel.Day.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        if model.day == .pick {
                            DatePicker("Date", selection: $model.pickedDate, displayedComponents: .date)
                                .tint(Theme.apricot)
                                .foregroundStyle(Theme.textPrimary)
                        }

                        if let error = model.errorMessage {
                            ErrorBanner(message: error) { Task { await model.load(api: settings.api) } }
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Theme.apricot)
                            TextField("Add a todo for \(LocalDate.display(model.selectedDate()))", text: $model.newTodoText)
                                .focused($addFocused)
                                .foregroundStyle(Theme.textPrimary)
                                .submitLabel(.done)
                                .onSubmit {
                                    Task {
                                        await model.add(api: settings.api)
                                        addFocused = true
                                    }
                                }
                        }
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(model.todos.enumerated()), id: \.element.id) { idx, todo in
                                TodoRow(todo: todo, showDate: false) {
                                    Task { await model.toggle(todo, api: settings.api) }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                if idx < model.todos.count - 1 {
                                    Divider().background(Theme.divider).padding(.leading, 44)
                                }
                            }
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 120)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: "\(model.selectedDate())|\(settings.baseURL)|\(settings.token)") {
                await model.load(api: settings.api)
            }
        }
    }
}

private struct TodoRow: View {
    let todo: Todo
    let showDate: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                OrganicCheckbox(checked: todo.done)
                VStack(alignment: .leading, spacing: 2) {
                    Text(todo.text)
                        .strikethrough(todo.done, color: Theme.textTertiary)
                        .foregroundStyle(todo.done ? Theme.textSecondary : Theme.textPrimary)
                    if showDate {
                        Text(LocalDate.display(todo.dueDate))
                            .font(.caption)
                            .foregroundStyle(Theme.terracotta)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
