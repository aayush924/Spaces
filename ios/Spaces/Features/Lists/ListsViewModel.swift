import Foundation
import Observation

@MainActor
@Observable
final class ListsViewModel {
    enum Segment: String, CaseIterable, Identifiable {
        case today = "Today"
        case tomorrow = "Tomorrow"
        case lists = "Lists"
        var id: String { rawValue }
    }

    var selectedSegment: Segment = .today
    private(set) var lists: [ListSummary] = []
    private(set) var itemsByList: [String: [ListItem]] = [:]
    private(set) var tomorrowTodos: [Todo] = []
    private(set) var todayTodos: [Todo] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    func inlineItems(for listID: String) -> [ListItem] {
        itemsByList[listID] ?? []
    }

    func load(api: APIClient, isConfigured: Bool = true) async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetchedListsTask = api.lists()
            async let fetchedTomorrowTask = api.todos(date: LocalDate.tomorrow())
            async let fetchedTodayTask = api.todos(date: LocalDate.today())
            let (fetchedLists, fetchedTomorrow, fetchedToday) = try await (
                fetchedListsTask,
                fetchedTomorrowTask,
                fetchedTodayTask
            )
            lists = fetchedLists
            // Load items for the first list so its inline card checklist renders immediately.
            if let first = fetchedLists.first {
                if let firstItems = try? await api.listItems(listID: first.id) {
                    itemsByList[first.id] = firstItems
                }
            }
            tomorrowTodos = fetchedTomorrow
            todayTodos = fetchedToday
            hasLoaded = true
            errorMessage = nil
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func toggleInlineItem(_ item: ListItem, in listID: String, api: APIClient, isConfigured: Bool = true) async {
        guard var listItems = itemsByList[listID],
              let index = listItems.firstIndex(where: { $0.id == item.id }) else { return }
        listItems[index].done.toggle()
        itemsByList[listID] = listItems
        updateListCounts(for: listID)

        guard isConfigured, !item.id.hasPrefix("showcase-") else { return }
        do {
            let updated = try await api.updateListItem(listID: listID, itemID: item.id, done: listItems[index].done)
            if var current = itemsByList[listID], let i = current.firstIndex(where: { $0.id == updated.id }) {
                current[i] = updated
                itemsByList[listID] = current
                updateListCounts(for: listID)
            }
        } catch {
            if var current = itemsByList[listID], let i = current.firstIndex(where: { $0.id == item.id }) {
                current[i].done = item.done
                itemsByList[listID] = current
                updateListCounts(for: listID)
            }
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    private func updateListCounts(for listID: String) {
        guard let i = lists.firstIndex(where: { $0.id == listID }),
              let items = itemsByList[listID] else { return }
        lists[i].itemCount = items.count
        lists[i].openCount = items.filter { !$0.done }.count
    }

    func toggleTodo(_ todo: Todo, isToday: Bool, api: APIClient, isConfigured: Bool = true) async {
        if isToday {
            if let idx = todayTodos.firstIndex(where: { $0.id == todo.id }) {
                todayTodos[idx].done.toggle()
            }
        } else {
            if let idx = tomorrowTodos.firstIndex(where: { $0.id == todo.id }) {
                tomorrowTodos[idx].done.toggle()
            }
        }
        guard isConfigured, !todo.id.hasPrefix("showcase-") else { return }
        do {
            let updated = try await api.updateTodo(id: todo.id, done: !todo.done)
            if isToday, let idx = todayTodos.firstIndex(where: { $0.id == todo.id }) {
                todayTodos[idx] = updated
            } else if let idx = tomorrowTodos.firstIndex(where: { $0.id == todo.id }) {
                tomorrowTodos[idx] = updated
            }
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func addQuickTodo(text: String, forToday: Bool, api: APIClient, isConfigured: Bool = true) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let due = forToday ? LocalDate.today() : LocalDate.tomorrow()
        if !isConfigured {
            let newTodo = Todo(
                id: "showcase-\(UUID().uuidString)",
                text: trimmed,
                dueDate: due,
                done: false,
                doneAt: nil,
                createdAt: Date()
            )
            if forToday {
                todayTodos.append(newTodo)
            } else {
                tomorrowTodos.append(newTodo)
            }
            return true
        }
        do {
            let created = try await api.createTodo(text: trimmed, dueDate: due)
            if forToday {
                todayTodos.append(created)
            } else {
                tomorrowTodos.append(created)
            }
            return true
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
            return false
        }
    }

    func create(name: String, kind: ListKind, api: APIClient, isConfigured: Bool = true) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if !isConfigured {
            let created = ListSummary(
                id: "showcase-\(UUID().uuidString)",
                name: trimmed,
                slug: trimmed.lowercased().replacingOccurrences(of: " ", with: "-"),
                kind: kind.rawValue,
                itemCount: 0,
                openCount: 0,
                createdAt: Date()
            )
            lists.append(created)
            itemsByList[created.id] = []
            return true
        }
        do {
            let created = try await api.createList(name: trimmed, kind: kind)
            if let index = lists.firstIndex(where: { $0.id == created.id }) {
                lists[index] = created
            } else {
                lists.append(created)
            }
            return true
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
            return false
        }
    }

    func delete(_ list: ListSummary, api: APIClient, isConfigured: Bool = true) async {
        let snapshot = lists
        let itemsSnapshot = itemsByList[list.id]
        lists.removeAll { $0.id == list.id }
        itemsByList.removeValue(forKey: list.id)
        guard isConfigured, !list.id.hasPrefix("showcase-") else { return }
        do {
            try await api.deleteList(id: list.id)
            if let first = lists.first, itemsByList[first.id] == nil {
                if let firstItems = try? await api.listItems(listID: first.id) {
                    itemsByList[first.id] = firstItems
                }
            }
        } catch {
            lists = snapshot
            if let itemsSnapshot {
                itemsByList[list.id] = itemsSnapshot
            }
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }
}

@MainActor
@Observable
final class ListDetailViewModel {
    let listID: String
    private(set) var items: [ListItem] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var newItemText = ""
    var errorMessage: String?

    init(listID: String) {
        self.listID = listID
        if listID == "showcase-costco" {
            self.items = ShowcaseData.costcoItems
            self.hasLoaded = true
        } else if listID == "showcase-wishlist" {
            self.items = ShowcaseData.wishListItems
            self.hasLoaded = true
        }
    }

    var openItems: [ListItem] { items.filter { !$0.done } }
    var doneItems: [ListItem] { items.filter(\.done) }

    func load(api: APIClient, isConfigured: Bool = true) async {
        guard isConfigured, !listID.hasPrefix("showcase-") else {
            hasLoaded = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await api.listItems(listID: listID)
            hasLoaded = true
            errorMessage = nil
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func add(api: APIClient, isConfigured: Bool = true) async {
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        newItemText = ""
        if !isConfigured || listID.hasPrefix("showcase-") {
            items.append(
                ListItem(
                    id: "showcase-\(UUID().uuidString)",
                    listId: listID,
                    text: text,
                    quantity: "1",
                    done: false,
                    createdAt: Date()
                )
            )
            return
        }
        do {
            let item = try await api.addListItem(listID: listID, text: text)
            items.append(item)
        } catch {
            newItemText = text
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func toggle(_ item: ListItem, api: APIClient, isConfigured: Bool = true) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].done.toggle()
        guard isConfigured, !item.id.hasPrefix("showcase-") else { return }
        do {
            let updated = try await api.updateListItem(listID: listID, itemID: item.id, done: items[index].done)
            if let i = items.firstIndex(where: { $0.id == updated.id }) { items[i] = updated }
        } catch {
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].done = item.done }
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func delete(_ item: ListItem, api: APIClient, isConfigured: Bool = true) async {
        let snapshot = items
        items.removeAll { $0.id == item.id }
        guard isConfigured, !item.id.hasPrefix("showcase-") else { return }
        do {
            try await api.deleteListItem(listID: listID, itemID: item.id)
        } catch {
            items = snapshot
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }

    func clearCompleted(api: APIClient, isConfigured: Bool = true) async {
        let snapshot = items
        items.removeAll(where: \.done)
        guard isConfigured, !listID.hasPrefix("showcase-") else { return }
        do {
            _ = try await api.clearCompleted(listID: listID)
        } catch {
            items = snapshot
            if let message = userMessage(for: error) { errorMessage = message }
        }
    }
}
