import Foundation
import Observation

@MainActor
@Observable
final class TodosViewModel {
    enum Segment: String, CaseIterable, Identifiable {
        case today = "Today"
        case later = "Later"
        var id: String { rawValue }
    }

    var selectedSegment: Segment = .today
    private(set) var todayTodos: [Todo] = []
    private(set) var laterTodos: [Todo] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    func load(api: APIClient, isConfigured: Bool = true) async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        let today = LocalDate.today()
        do {
            async let fetchedTodayTask = api.todos(date: today)
            async let fetchedLaterTask = api.laterTodos(after: today)
            let (fetchedToday, fetchedLater) = try await (fetchedTodayTask, fetchedLaterTask)
            todayTodos = fetchedToday
            laterTodos = fetchedLater
            hasLoaded = true
            errorMessage = nil
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func toggleTodo(_ todo: Todo, isToday: Bool, api: APIClient, isConfigured: Bool = true) async {
        if isToday {
            if let idx = todayTodos.firstIndex(where: { $0.id == todo.id }) {
                todayTodos[idx].done.toggle()
            }
        } else {
            if let idx = laterTodos.firstIndex(where: { $0.id == todo.id }) {
                laterTodos[idx].done.toggle()
            }
        }
        guard isConfigured, !todo.id.hasPrefix("showcase-") else { return }
        do {
            let updated = try await api.updateTodo(id: todo.id, done: !todo.done)
            if isToday, let idx = todayTodos.firstIndex(where: { $0.id == todo.id }) {
                todayTodos[idx] = updated
            } else if let idx = laterTodos.firstIndex(where: { $0.id == todo.id }) {
                laterTodos[idx] = updated
            }
        } catch {
            if isToday, let idx = todayTodos.firstIndex(where: { $0.id == todo.id }) {
                todayTodos[idx].done = todo.done
            } else if let idx = laterTodos.firstIndex(where: { $0.id == todo.id }) {
                laterTodos[idx].done = todo.done
            }
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func addTodo(text: String, dueDate: String, api: APIClient, isConfigured: Bool = true) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let today = LocalDate.today()
        let isToday = (dueDate == today)
        if !isConfigured {
            let newTodo = Todo(
                id: "showcase-\(UUID().uuidString)",
                text: trimmed,
                dueDate: dueDate,
                done: false,
                doneAt: nil,
                createdAt: Date()
            )
            if isToday {
                todayTodos.append(newTodo)
            } else {
                laterTodos.append(newTodo)
                laterTodos.sort { ($0.dueDate, $0.createdAt) < ($1.dueDate, $1.createdAt) }
            }
            return true
        }
        do {
            let created = try await api.createTodo(text: trimmed, dueDate: dueDate)
            if isToday {
                todayTodos.append(created)
            } else {
                laterTodos.append(created)
                laterTodos.sort { ($0.dueDate, $0.createdAt) < ($1.dueDate, $1.createdAt) }
            }
            return true
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
            return false
        }
    }
}
