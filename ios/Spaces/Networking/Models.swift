import Foundation

// MARK: - Core models (mirror docs/API.md exactly; JSON is snake_case and is
// converted by `JSONCoding.decoder` using `.convertFromSnakeCase`).

struct Note: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var text: String
    var title: String?
    var tags: [String]
    let createdAt: Date
    var updatedAt: Date

    init(id: String, text: String, title: String?, tags: [String], createdAt: Date, updatedAt: Date) {
        self.id = id
        self.text = text
        self.title = title
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    /// Title if present, otherwise the first line of the text.
    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "Untitled note" : firstLine
    }
}

struct ListSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var slug: String
    /// "shopping" | "wishlist" | "custom" (kept as String to tolerate new kinds).
    var kind: String
    var itemCount: Int
    var openCount: Int
    let createdAt: Date

    var symbolName: String {
        switch kind {
        case "shopping": return "cart"
        case "wishlist": return "gift"
        default: return "list.bullet"
        }
    }
}

enum ListKind: String, CaseIterable, Identifiable, Sendable {
    case shopping, wishlist, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .shopping: return "Shopping"
        case .wishlist: return "Wish list"
        case .custom: return "Custom"
        }
    }
}

struct ListItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let listId: String
    var text: String
    var quantity: String?
    var done: Bool
    let createdAt: Date
}

struct Todo: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var text: String
    /// Calendar date "YYYY-MM-DD".
    var dueDate: String
    var done: Bool
    var doneAt: Date?
    let createdAt: Date
}

enum ActionType: Hashable, Sendable, Codable {
    case note
    case listAdd
    case todoAdd
    case todoComplete
    case listItemRemove
    case unknown(String)

    var rawValue: String {
        switch self {
        case .note: return "note"
        case .listAdd: return "list_add"
        case .todoAdd: return "todo_add"
        case .todoComplete: return "todo_complete"
        case .listItemRemove: return "list_item_remove"
        case .unknown(let raw): return raw
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "note": self = .note
        case "list_add": self = .listAdd
        case "todo_add": self = .todoAdd
        case "todo_complete": self = .todoComplete
        case "list_item_remove": self = .listItemRemove
        default: self = .unknown(rawValue)
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

struct ExecutedAction: Codable, Hashable, Sendable {
    let type: ActionType
    let summary: String
    let confidence: Double?
    let noteId: String?
    let listId: String?
    let listName: String?
    /// Calendar date "YYYY-MM-DD" for todo ops.
    let dueDate: String?
    let items: [String]

    init(type: ActionType, summary: String, confidence: Double? = nil, noteId: String? = nil,
         listId: String? = nil, listName: String? = nil, dueDate: String? = nil, items: [String] = []) {
        self.type = type
        self.summary = summary
        self.confidence = confidence
        self.noteId = noteId
        self.listId = listId
        self.listName = listName
        self.dueDate = dueDate
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(ActionType.self, forKey: .type)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        noteId = try c.decodeIfPresent(String.self, forKey: .noteId)
        listId = try c.decodeIfPresent(String.self, forKey: .listId)
        listName = try c.decodeIfPresent(String.self, forKey: .listName)
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
    }
}

struct Suggestion: Codable, Hashable, Sendable {
    let label: String
    let listName: String?
    let items: [String]

    init(label: String, listName: String?, items: [String]) {
        self.label = label
        self.listName = listName
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        listName = try c.decodeIfPresent(String.self, forKey: .listName)
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
    }
}

struct CaptureResponse: Codable, Hashable, Sendable {
    let captureId: String
    let summary: String
    let actions: [ExecutedAction]
    let suggestions: [Suggestion]

    init(captureId: String, summary: String, actions: [ExecutedAction], suggestions: [Suggestion]) {
        self.captureId = captureId
        self.summary = summary
        self.actions = actions
        self.suggestions = suggestions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        captureId = try c.decode(String.self, forKey: .captureId)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        actions = try c.decodeIfPresent([ExecutedAction].self, forKey: .actions) ?? []
        suggestions = try c.decodeIfPresent([Suggestion].self, forKey: .suggestions) ?? []
    }
}

/// History entry from `GET /captures`.
struct Capture: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let rawText: String
    let summary: String
    let actions: [ExecutedAction]
    let suggestions: [Suggestion]
    var undone: Bool
    let createdAt: Date

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        rawText = try c.decodeIfPresent(String.self, forKey: .rawText) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        actions = try c.decodeIfPresent([ExecutedAction].self, forKey: .actions) ?? []
        suggestions = try c.decodeIfPresent([Suggestion].self, forKey: .suggestions) ?? []
        undone = try c.decodeIfPresent(Bool.self, forKey: .undone) ?? false
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    var asResponse: CaptureResponse {
        CaptureResponse(captureId: id, summary: summary, actions: actions, suggestions: suggestions)
    }
}

struct SearchResult: Codable, Identifiable, Hashable, Sendable {
    let note: Note
    let score: Double
    /// "semantic" | "keyword" | "both"
    let match: String
    var id: String { note.id }
}

struct AskResponse: Codable, Hashable, Sendable {
    let answer: String
    let citations: [Note]
}

struct HealthResponse: Codable, Hashable, Sendable {
    let status: String
    let db: Bool?
}

struct UndoResponse: Codable, Hashable, Sendable {
    let undone: Bool
}

struct DeletedResponse: Codable, Hashable, Sendable {
    let deleted: Int
}

struct AuthResponse: Codable, Hashable, Sendable {
    let token: String
    let email: String
    let name: String
}

struct ProfileResponse: Codable, Hashable, Sendable {
    let email: String
    let name: String
}

// MARK: - Request bodies (encoded with `.convertToSnakeCase`; nil optionals are omitted)

struct AuthRequest: Encodable, Sendable {
    let email: String
    let password: String
}

struct ProfilePatchRequest: Encodable, Sendable {
    let name: String
}

struct CaptureRequest: Encodable, Sendable {
    let text: String
    let timezone: String
    let clientNow: Date?
}

struct AskRequest: Encodable, Sendable {
    let question: String
}

struct NoteCreateRequest: Encodable, Sendable {
    let text: String
    var title: String?
    var tags: [String]?
}

struct NotePatchRequest: Encodable, Sendable {
    var text: String?
    var title: String?
    var tags: [String]?
}

struct ListCreateRequest: Encodable, Sendable {
    let name: String
    var kind: String?
}

struct ListItemCreateRequest: Encodable, Sendable {
    let text: String
    var quantity: String?
}

struct ListItemPatchRequest: Encodable, Sendable {
    var text: String?
    var quantity: String?
    var done: Bool?
}

struct TodoCreateRequest: Encodable, Sendable {
    let text: String
    let dueDate: String
}

struct TodoPatchRequest: Encodable, Sendable {
    var text: String?
    var dueDate: String?
    var done: Bool?
}
