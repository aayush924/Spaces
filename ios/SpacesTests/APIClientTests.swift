import XCTest
@testable import Spaces

/// Intercepts URLSession requests so APIClient can be tested without a server.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int = 200
        var body: String = "{}"
    }

    nonisolated(unsafe) static var stub = Stub()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? Self.read(request.httpBodyStream)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.stub.status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class APIClientTests: XCTestCase {
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        client = APIClient(baseURL: "http://localhost:8000/", token: "secret", session: URLSession(configuration: config))
        StubURLProtocol.stub = .init()
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
    }

    private func bodyJSON() throws -> [String: Any] {
        let data = try XCTUnwrap(StubURLProtocol.lastBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Request building

    func testMakeRequestBuildsURLMethodAndAuth() throws {
        let request = try client.makeRequest(.get, "todos", query: [URLQueryItem(name: "date", value: "2026-10-09")])
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8000/todos?date=2026-10-09")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertNil(request.httpBody)
    }

    func testPlusSignInQueryIsEscaped() throws {
        let request = try client.makeRequest(.get, "/search", query: [URLQueryItem(name: "q", value: "c++ ideas")])
        XCTAssertEqual(request.url?.query, "q=c%2B%2B%20ideas")
    }

    func testBodyIsSnakeCaseAndOmitsNils() throws {
        let request = try client.makeRequest(.patch, "/todos/t1", body: TodoPatchRequest(dueDate: "2026-10-10", done: true))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["due_date"] as? String, "2026-10-10")
        XCTAssertEqual(json["done"] as? Bool, true)
        XCTAssertNil(json["text"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testHealthIsUnauthenticatedAndMissingTokenThrows() throws {
        let anon = APIClient(baseURL: "http://localhost:8000", token: "  ")
        let health = try anon.makeRequest(.get, "/health", authorized: false)
        XCTAssertNil(health.value(forHTTPHeaderField: "Authorization"))
        XCTAssertThrowsError(try anon.makeRequest(.get, "/lists")) { XCTAssertEqual($0 as? APIError, .missingToken) }
    }

    func testInvalidBaseURLThrows() {
        for bad in ["", "localhost:8000", "ftp://host", "http://"] {
            let c = APIClient(baseURL: bad, token: "t")
            XCTAssertThrowsError(try c.makeRequest(.get, "/lists"), bad)
        }
    }

    // MARK: Round trips through the stub

    func testCaptureSendsTimezoneAndDecodesResponse() async throws {
        StubURLProtocol.stub.body = #"{"capture_id":"c1","summary":"✓ Note saved","actions":[{"type":"note","summary":"Note saved","note_id":"n1","items":[]}],"suggestions":[]}"#
        let now = try XCTUnwrap(ISOTimestamp.parse("2026-10-08T22:00:00Z"))
        let response = try await client.capture(text: "an idea", timeZone: TimeZone(identifier: "America/Los_Angeles")!, now: now)

        XCTAssertEqual(response.captureId, "c1")
        XCTAssertEqual(response.actions.first?.noteId, "n1")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/capture")
        let body = try bodyJSON()
        XCTAssertEqual(body["text"] as? String, "an idea")
        XCTAssertEqual(body["timezone"] as? String, "America/Los_Angeles")
        XCTAssertEqual(body["client_now"] as? String, "2026-10-08T22:00:00Z")
    }

    func testListItemEndpointsUseCorrectPaths() async throws {
        StubURLProtocol.stub.body = #"{"id":"i1","list_id":"l1","text":"eggs","quantity":"12","done":true,"created_at":"2026-10-08T22:00:00Z"}"#
        let item = try await client.updateListItem(listID: "l1", itemID: "i1", done: true)
        XCTAssertTrue(item.done)
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "PATCH")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/lists/l1/items/i1")

        StubURLProtocol.stub.body = #"{"deleted":2}"#
        let cleared = try await client.clearCompleted(listID: "l1")
        XCTAssertEqual(cleared.deleted, 2)
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.query, "done=true")
    }

    func testOverdueQueryParameter() async throws {
        StubURLProtocol.stub.body = "[]"
        let todos = try await client.overdueTodos(before: "2026-10-08")
        XCTAssertTrue(todos.isEmpty)
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.query, "overdue_before=2026-10-08")
    }

    func testHTTPErrorSurfacesFastAPIDetail() async {
        StubURLProtocol.stub = .init(status: 401, body: #"{"detail":"Invalid or missing API token"}"#)
        do {
            _ = try await client.lists()
            XCTFail("expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 401, detail: "Invalid or missing API token"))
            XCTAssertTrue(error.errorDescription?.contains("Settings") == true)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testValidationErrorArrayIsFlattened() {
        let data = Data(#"{"detail":[{"msg":"field required"},{"msg":"must be YYYY-MM-DD"}]}"#.utf8)
        XCTAssertEqual(APIClient.errorDetail(from: data, status: 422), "field required; must be YYYY-MM-DD")
    }

    func testDecodingErrorIsReported() async {
        StubURLProtocol.stub.body = #"{"unexpected":true}"#
        do {
            _ = try await client.health()
            XCTFail("expected decoding error")
        } catch let error as APIError {
            if case .decoding = error {} else { XCTFail("wrong error \(error)") }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
