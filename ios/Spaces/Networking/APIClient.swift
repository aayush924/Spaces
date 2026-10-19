import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum APIError: LocalizedError, Equatable {
    case invalidBaseURL(String)
    case missingToken
    case http(status: Int, detail: String)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let url):
            return "The server URL “\(url)” is not valid. Check Settings."
        case .missingToken:
            return "No API token set. Add it in Settings."
        case .http(let status, let detail):
            if status == 401 || status == 403 { return "Unauthorized (\(status)): \(detail). Check your API token in Settings." }
            return "\(detail) (HTTP \(status))"
        case .transport(let message):
            return "Can’t reach the server: \(message)"
        case .decoding(let message):
            return "Unexpected server response: \(message)"
        }
    }

    var statusCode: Int? {
        if case .http(let status, _) = self { return status }
        return nil
    }
}

/// Thin async/await wrapper around URLSession for the Spaces API.
struct APIClient: Sendable {
    let baseURL: String
    let token: String
    let session: URLSession

    init(baseURL: String, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    // MARK: Request building

    /// Builds (but does not send) a request. Exposed for unit tests.
    func makeRequest(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        authorized: Bool = true
    ) throws -> URLRequest {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path

        guard !base.isEmpty,
              var components = URLComponents(string: base + normalizedPath),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host?.isEmpty == false
        else { throw APIError.invalidBaseURL(baseURL) }

        if !query.isEmpty {
            components.queryItems = query
            // URLComponents leaves "+" unescaped, which servers decode as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw APIError.invalidBaseURL(baseURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 60 // LLM-backed endpoints can be slow
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if authorized {
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedToken.isEmpty else { throw APIError.missingToken }
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONCoding.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    // MARK: Sending

    /// Sends a request and returns the raw body of a 2xx response.
    @discardableResult
    func data(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        authorized: Bool = true
    ) async throws -> Data {
        let request = try makeRequest(method, path, query: query, body: body, authorized: authorized)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, detail: Self.errorDetail(from: data, status: http.statusCode))
        }
        return data
    }

    /// Sends a request and decodes a JSON response.
    func request<T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        authorized: Bool = true,
        as type: T.Type = T.self
    ) async throws -> T {
        let data = try await data(method, path, query: query, body: body, authorized: authorized)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(Self.describe(error))
        }
    }

    // MARK: Error helpers

    /// Extracts FastAPI's `{"detail": ...}` message. `detail` may be a string or
    /// (for 422 validation errors) an array of `{"msg": ...}` objects.
    static func errorDetail(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = object["detail"] {
            if let string = detail as? String { return string }
            if let array = detail as? [[String: Any]] {
                let messages = array.compactMap { $0["msg"] as? String }
                if !messages.isEmpty { return messages.joined(separator: "; ") }
            }
            return String(describing: detail)
        }
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty, text.count < 300 {
            return text
        }
        return HTTPURLResponse.localizedString(forStatusCode: status).capitalized
    }

    private static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        func path(_ codingPath: [CodingKey]) -> String {
            codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context.codingPath))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(context.debugDescription) at \(path(context.codingPath))"
        @unknown default:
            return decodingError.localizedDescription
        }
    }
}

// MARK: - Endpoints (see docs/API.md)

extension APIClient {
    private func seg(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
    }

    // Health
    func health() async throws -> HealthResponse {
        try await request(.get, "/health", authorized: false)
    }

    // Auth & Profile
    func signup(email: String, password: String) async throws -> AuthResponse {
        try await request(.post, "/auth/signup", body: AuthRequest(email: email, password: password), authorized: false)
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await request(.post, "/auth/login", body: AuthRequest(email: email, password: password), authorized: false)
    }

    func updateProfile(name: String) async throws -> ProfileResponse {
        try await request(.patch, "/auth/profile", body: ProfilePatchRequest(name: name))
    }

    // Capture
    func capture(text: String, timeZone: TimeZone = .current, now: Date = Date()) async throws -> CaptureResponse {
        try await request(.post, "/capture",
                          body: CaptureRequest(text: text, timezone: timeZone.identifier, clientNow: now))
    }

    func captures(limit: Int = 20) async throws -> [Capture] {
        try await request(.get, "/captures", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func undoCapture(id: String) async throws -> UndoResponse {
        try await request(.post, "/capture/\(seg(id))/undo")
    }

    func acceptSuggestion(captureID: String, index: Int) async throws -> CaptureResponse {
        try await request(.post, "/capture/\(seg(captureID))/suggestions/\(index)/accept")
    }

    // Search
    func search(_ query: String, limit: Int = 20) async throws -> [SearchResult] {
        try await request(.get, "/search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    func ask(_ question: String) async throws -> AskResponse {
        try await request(.post, "/ask", body: AskRequest(question: question))
    }

    // Notes
    func notes(limit: Int = 50, before: Date? = nil) async throws -> [Note] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before { query.append(URLQueryItem(name: "before", value: ISOTimestamp.string(from: before))) }
        return try await request(.get, "/notes", query: query)
    }

    func createNote(text: String, title: String? = nil, tags: [String]? = nil) async throws -> Note {
        try await request(.post, "/notes", body: NoteCreateRequest(text: text, title: title, tags: tags))
    }

    func note(id: String) async throws -> Note {
        try await request(.get, "/notes/\(seg(id))")
    }

    func updateNote(id: String, text: String? = nil, title: String? = nil, tags: [String]? = nil) async throws -> Note {
        try await request(.patch, "/notes/\(seg(id))", body: NotePatchRequest(text: text, title: title, tags: tags))
    }

    func deleteNote(id: String) async throws {
        try await data(.delete, "/notes/\(seg(id))")
    }

    // Lists
    func lists() async throws -> [ListSummary] {
        try await request(.get, "/lists")
    }

    func createList(name: String, kind: ListKind? = nil) async throws -> ListSummary {
        try await request(.post, "/lists", body: ListCreateRequest(name: name, kind: kind?.rawValue))
    }

    func deleteList(id: String) async throws {
        try await data(.delete, "/lists/\(seg(id))")
    }

    func listItems(listID: String) async throws -> [ListItem] {
        try await request(.get, "/lists/\(seg(listID))/items")
    }

    func addListItem(listID: String, text: String, quantity: String? = nil) async throws -> ListItem {
        try await request(.post, "/lists/\(seg(listID))/items",
                          body: ListItemCreateRequest(text: text, quantity: quantity))
    }

    func updateListItem(listID: String, itemID: String, text: String? = nil,
                        quantity: String? = nil, done: Bool? = nil) async throws -> ListItem {
        try await request(.patch, "/lists/\(seg(listID))/items/\(seg(itemID))",
                          body: ListItemPatchRequest(text: text, quantity: quantity, done: done))
    }

    func deleteListItem(listID: String, itemID: String) async throws {
        try await data(.delete, "/lists/\(seg(listID))/items/\(seg(itemID))")
    }

    func clearCompleted(listID: String) async throws -> DeletedResponse {
        try await request(.delete, "/lists/\(seg(listID))/items",
                          query: [URLQueryItem(name: "done", value: "true")])
    }

    // Todos
    func todos(date: String) async throws -> [Todo] {
        try await request(.get, "/todos", query: [URLQueryItem(name: "date", value: date)])
    }

    func overdueTodos(before date: String) async throws -> [Todo] {
        try await request(.get, "/todos", query: [URLQueryItem(name: "overdue_before", value: date)])
    }

    func createTodo(text: String, dueDate: String) async throws -> Todo {
        try await request(.post, "/todos", body: TodoCreateRequest(text: text, dueDate: dueDate))
    }

    func updateTodo(id: String, text: String? = nil, dueDate: String? = nil, done: Bool? = nil) async throws -> Todo {
        try await request(.patch, "/todos/\(seg(id))", body: TodoPatchRequest(text: text, dueDate: dueDate, done: done))
    }

    func deleteTodo(id: String) async throws {
        try await data(.delete, "/todos/\(seg(id))")
    }
}
