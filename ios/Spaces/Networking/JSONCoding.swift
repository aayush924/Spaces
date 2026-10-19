import Foundation

/// Shared JSON encoder/decoder configured for the Spaces API contract.
enum JSONCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ISOTimestamp.parse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 timestamp: \(string)"
                )
            }
            return date
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISOTimestamp.string(from: date))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}

/// Tolerant ISO-8601 timestamp parsing.
///
/// Accepts `2026-10-08T22:10:00Z`, `2026-10-08T22:10:00.123Z`,
/// `2026-10-08T22:10:00.123456+00:00`, a space instead of `T`, and naive timestamps
/// without any zone designator (interpreted as UTC, which is what the backend stores).
enum ISOTimestamp {
    private static let parser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let writer: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 19 else { return nil }

        // Allow "YYYY-MM-DD HH:MM:SS" (Python's str(datetime)).
        let separator = s[s.index(s.startIndex, offsetBy: 10)]
        if separator == " " || separator == "t" {
            s = String(s.prefix(10)) + "T" + String(s.dropFirst(11))
        } else if separator != "T" {
            return nil
        }
        let tIndex = s.index(s.startIndex, offsetBy: 10)

        // Strip fractional seconds (any number of digits) and add them back afterwards,
        // so precision beyond milliseconds (Python microseconds) never breaks parsing.
        var fraction: TimeInterval = 0
        if let dot = s[tIndex...].firstIndex(of: ".") {
            var end = s.index(after: dot)
            while end < s.endIndex, s[end].isASCII, s[end].isNumber {
                end = s.index(after: end)
            }
            let digits = s[s.index(after: dot)..<end]
            if !digits.isEmpty {
                fraction = Double("0." + digits) ?? 0
            }
            s.removeSubrange(dot..<end)
        }

        // Add "Z" if there is no zone designator after the time.
        let timePart = s.dropFirst(11)
        let hasZone = timePart.hasSuffix("Z") || timePart.hasSuffix("z")
            || timePart.contains("+") || timePart.contains("-")
        if !hasZone {
            s += "Z"
        } else if s.hasSuffix("z") {
            s.removeLast()
            s += "Z"
        }

        guard let base = parser.date(from: s) else { return nil }
        return base.addingTimeInterval(fraction)
    }

    /// Formats as `2026-10-08T22:10:00Z` (UTC, whole seconds).
    static func string(from date: Date) -> String {
        writer.string(from: date)
    }
}

/// Helpers for calendar dates ("YYYY-MM-DD") which are always expressed in the
/// user's *local* calendar/time zone (the server never guesses the client's day).
enum LocalDate {
    private static func makeFormatter(timeZone: TimeZone, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        var cal = calendar
        cal.timeZone = timeZone
        f.calendar = cal
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// Formats a moment as the local calendar day, e.g. "2026-10-09".
    static func string(from date: Date, timeZone: TimeZone = .current,
                       calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        makeFormatter(timeZone: timeZone, calendar: calendar).string(from: date)
    }

    /// Parses "YYYY-MM-DD" to local midnight of that day.
    static func date(from string: String, timeZone: TimeZone = .current,
                     calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        makeFormatter(timeZone: timeZone, calendar: calendar).date(from: string)
    }

    static func today(now: Date = Date()) -> String { string(from: now) }

    static func tomorrow(now: Date = Date()) -> String {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return string(from: next)
    }

    /// Human label: "Today", "Tomorrow", "Yesterday" or e.g. "Fri, Oct 9".
    static func display(_ yyyyMMdd: String, now: Date = Date()) -> String {
        if yyyyMMdd == today(now: now) { return "Today" }
        if yyyyMMdd == tomorrow(now: now) { return "Tomorrow" }
        if let y = Calendar.current.date(byAdding: .day, value: -1, to: now), yyyyMMdd == string(from: y) {
            return "Yesterday"
        }
        guard let date = date(from: yyyyMMdd) else { return yyyyMMdd }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
