import XCTest
@testable import Spaces

/// Decodes every model using sample payloads from docs/API.md.
final class ModelDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONCoding.decoder.decode(T.self, from: Data(json.utf8))
    }

    func testNoteDecodesWithAndWithoutFractionalSeconds() throws {
        let note = try decode(Note.self, """
        {"id":"n1","text":"Pegboard wall","title":"Garage bike storage","tags":["garage","idea"],
         "created_at":"2026-10-08T22:10:00.123Z","updated_at":"2026-10-08T22:10:00Z"}
        """)
        XCTAssertEqual(note.id, "n1")
        XCTAssertEqual(note.title, "Garage bike storage")
        XCTAssertEqual(note.tags, ["garage", "idea"])
        XCTAssertEqual(note.createdAt.timeIntervalSince1970, 1_791_497_400.123, accuracy: 0.001)
        XCTAssertEqual(note.updatedAt.timeIntervalSince1970, 1_791_497_400, accuracy: 0.001)
    }

    func testNoteToleratesMissingOptionalFields() throws {
        let note = try decode(Note.self, #"{"id":"n2","created_at":"2026-10-08T22:10:00.123456+00:00"}"#)
        XCTAssertEqual(note.text, "")
        XCTAssertNil(note.title)
        XCTAssertEqual(note.tags, [])
        XCTAssertEqual(note.updatedAt, note.createdAt)
        XCTAssertEqual(note.displayTitle, "Untitled note")
    }

    func testListSummaryAndItem() throws {
        let list = try decode(ListSummary.self, """
        {"id":"l1","name":"Costco","slug":"costco","kind":"shopping","item_count":5,"open_count":3,
         "created_at":"2026-10-08T22:10:00Z"}
        """)
        XCTAssertEqual(list.openCount, 3)
        XCTAssertEqual(list.itemCount, 5)
        XCTAssertEqual(list.symbolName, "cart")

        let item = try decode(ListItem.self, """
        {"id":"i1","list_id":"l1","text":"paper towels","quantity":null,"done":false,
         "created_at":"2026-10-08T22:10:00Z"}
        """)
        XCTAssertEqual(item.listId, "l1")
        XCTAssertNil(item.quantity)
        XCTAssertFalse(item.done)
    }

    func testTodo() throws {
        let todo = try decode(Todo.self, """
        {"id":"t1","text":"call dentist","due_date":"2026-10-09","done":true,
         "done_at":"2026-10-09T17:00:00.5Z","created_at":"2026-10-08T22:10:00Z"}
        """)
        XCTAssertEqual(todo.dueDate, "2026-10-09")
        XCTAssertTrue(todo.done)
        XCTAssertNotNil(todo.doneAt)
    }

    func testCaptureResponseWithActionsAndSuggestions() throws {
        let response = try decode(CaptureResponse.self, """
        {"capture_id":"c1","summary":"✓ 2 items → Costco",
         "actions":[
           {"type":"list_add","summary":"2 items → Costco","confidence":0.93,"note_id":null,
            "list_id":"l1","list_name":"Costco","due_date":null,"items":["eggs","paper towels"]},
           {"type":"todo_add","summary":"1 todo for Tomorrow","confidence":0.9,"due_date":"2026-10-09",
            "items":["call dentist"]},
           {"type":"something_new","summary":"?"}
         ],
         "suggestions":[{"label":"Add “milk” to Costco","list_name":"Costco","items":["milk"]}]}
        """)
        XCTAssertEqual(response.actions.count, 3)
        XCTAssertEqual(response.actions[0].type, .listAdd)
        XCTAssertEqual(response.actions[0].items, ["eggs", "paper towels"])
        XCTAssertEqual(response.actions[1].type, .todoAdd)
        XCTAssertEqual(response.actions[1].dueDate, "2026-10-09")
        XCTAssertEqual(response.actions[2].type, .unknown("something_new"))
        XCTAssertEqual(response.actions[2].items, [])
        XCTAssertEqual(response.suggestions.first?.listName, "Costco")
    }

    func testCaptureHistory() throws {
        let captures = try decode([Capture].self, """
        [{"id":"c1","raw_text":"milk","summary":"✓ Note saved: milk","actions":[],"suggestions":[],
          "undone":true,"created_at":"2026-10-08T22:10:00.000Z"}]
        """)
        XCTAssertEqual(captures.first?.rawText, "milk")
        XCTAssertEqual(captures.first?.undone, true)
        XCTAssertEqual(captures.first?.asResponse.captureId, "c1")
    }

    func testSearchAndAsk() throws {
        let note = #"{"id":"n1","text":"t","title":null,"tags":[],"created_at":"2026-10-08T22:10:00Z","updated_at":"2026-10-08T22:10:00Z"}"#
        let results = try decode([SearchResult].self, #"[{"note":\#(note),"score":0.0312,"match":"both"}]"#)
        XCTAssertEqual(results.first?.id, "n1")
        XCTAssertEqual(results.first?.match, "both")

        let ask = try decode(AskResponse.self, #"{"answer":"You had an idea [1]","citations":[\#(note)]}"#)
        XCTAssertEqual(ask.citations.count, 1)
    }

    func testSmallResponses() throws {
        XCTAssertEqual(try decode(HealthResponse.self, #"{"status":"ok","db":true,"atlas_search":false}"#).db, true)
        XCTAssertTrue(try decode(UndoResponse.self, #"{"undone":true}"#).undone)
        XCTAssertEqual(try decode(DeletedResponse.self, #"{"deleted":3}"#).deleted, 3)
    }
}

final class DateHelperTests: XCTestCase {
    func testISOTimestampVariants() {
        let base = ISOTimestamp.parse("2026-10-08T22:10:00Z")
        XCTAssertNotNil(base)
        XCTAssertEqual(ISOTimestamp.parse("2026-10-08 22:10:00"), base) // naive → UTC
        XCTAssertEqual(ISOTimestamp.parse("2026-10-08T15:10:00-07:00"), base)
        XCTAssertEqual(ISOTimestamp.parse("2026-10-08T22:10:00.250Z")!.timeIntervalSince(base!), 0.25, accuracy: 0.0001)
        XCTAssertNil(ISOTimestamp.parse("not a date"))
        XCTAssertEqual(ISOTimestamp.string(from: base!), "2026-10-08T22:10:00Z")
    }

    func testLocalDateUsesGivenTimeZone() {
        // 2026-10-09T05:30Z is still Oct 8 in Los Angeles, already Oct 9 in UTC.
        let moment = ISOTimestamp.parse("2026-10-09T05:30:00Z")!
        XCTAssertEqual(LocalDate.string(from: moment, timeZone: TimeZone(identifier: "America/Los_Angeles")!), "2026-10-08")
        XCTAssertEqual(LocalDate.string(from: moment, timeZone: TimeZone(identifier: "UTC")!), "2026-10-09")
    }

    func testLocalDateRoundTripAndLabels() {
        let now = Date()
        let today = LocalDate.today(now: now)
        XCTAssertEqual(today.count, 10)
        XCTAssertEqual(LocalDate.date(from: today).map { LocalDate.string(from: $0) }, today)
        XCTAssertEqual(LocalDate.display(today, now: now), "Today")
        XCTAssertEqual(LocalDate.display(LocalDate.tomorrow(now: now), now: now), "Tomorrow")
    }
}
