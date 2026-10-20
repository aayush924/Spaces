import Foundation
import Observation

@MainActor
@Observable
final class ListsViewModel {
    private(set) var lists: [ListSummary] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    func load(api: APIClient, isConfigured: Bool = true) async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            lists = try await api.lists()
            hasLoaded = true
            errorMessage = nil
        } catch {
            if let message = userMessage(for: error) { errorMessage = message }
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
        lists.removeAll { $0.id == list.id }
        guard isConfigured, !list.id.hasPrefix("showcase-") else { return }
        do {
            try await api.deleteList(id: list.id)
        } catch {
            lists = snapshot
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
