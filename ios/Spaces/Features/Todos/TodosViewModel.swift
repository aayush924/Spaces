import Foundation
import Observation

@MainActor
@Observable
final class TodosViewModel {
    enum Day: String, CaseIterable, Identifiable {
        case today = "Today"
        case tomorrow = "Tomorrow"
        case pick = "Pick date"
        var id: String { rawValue }
    }

    var day: Day = .today
    var pickedDate = Date()
    var newTodoText = ""
    private(set) var todos: [Todo] = []
    private(set) var overdue: [Todo] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    /// The selected calendar day as "YYYY-MM-DD" in the user's time zone.
    func selectedDate(now: Date = Date()) -> String {
        switch day {
        case .today: return LocalDate.today(now: now)
        case .tomorrow: return LocalDate.tomorrow(now: now)
        case .pick: return LocalDate.string(from: pickedDate)
        }
    }

    var openTodos: [Todo] { todos.filter { !$0.done } }
    var doneTodos: [Todo] { todos.filter(\.done) }

    func load(api: APIClient) async {
        let date = selectedDate()
        isLoading = true
        defer { isLoading = false }
        do {
            async let dayTodos = api.todos(date: date)
            async let overdueTodos = api.overdueTodos(before: LocalDate.today())
            let (fetched, late) = try await (dayTodos, overdueTodos)
            guard date == selectedDate() else { return } // user switched day mid-flight
            todos = fetched
            overdue = late
            hasLoaded = true
            errorMessage = nil
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func add(api: APIClient) async {
        let text = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        newTodoText = ""
        do {
            let todo = try await api.createTodo(text: text, dueDate: selectedDate())
            todos.append(todo)
        } catch {
            newTodoText = text
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func toggle(_ todo: Todo, api: APIClient) async {
        let newValue = !todo.done
        apply(id: todo.id) { $0.done = newValue } // optimistic
        do {
            let updated = try await api.updateTodo(id: todo.id, done: newValue)
            apply(id: todo.id) { $0 = updated }
        } catch {
            apply(id: todo.id) { $0.done = todo.done }
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    /// Moves an overdue todo to today.
    func moveToToday(_ todo: Todo, api: APIClient) async {
        do {
            let updated = try await api.updateTodo(id: todo.id, dueDate: LocalDate.today())
            overdue.removeAll { $0.id == todo.id }
            if day == .today { todos.append(updated) }
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func delete(_ todo: Todo, api: APIClient) async {
        let (savedTodos, savedOverdue) = (todos, overdue)
        todos.removeAll { $0.id == todo.id }
        overdue.removeAll { $0.id == todo.id }
        do {
            try await api.deleteTodo(id: todo.id)
        } catch {
            (todos, overdue) = (savedTodos, savedOverdue)
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    private func apply(id: String, _ change: (inout Todo) -> Void) {
        if let i = todos.firstIndex(where: { $0.id == id }) { change(&todos[i]) }
        if let i = overdue.firstIndex(where: { $0.id == id }) { change(&overdue[i]) }
    }
}
