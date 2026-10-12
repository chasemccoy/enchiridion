import Foundation

/// A timestamp column as the server sends it: SQLite's `CURRENT_TIMESTAMP` text, `"YYYY-MM-DD HH:MM:SS"` in UTC with no
/// `T` or `Z`. The raw string is kept and encoded back unchanged, so a record round-trips byte for byte; `date` is
/// parsed once, at init, and is nil when the text isn't in that shape (`contentCreatedAt` is free text on the server,
/// though every live value is in it).
///
/// Equality and hashing follow `raw`. Ordering is by `date`, unparseable values first, with `raw` breaking ties.
public struct DBTimestamp: Codable, Hashable, Comparable, Sendable, ExpressibleByStringLiteral,
    CustomStringConvertible {
    public let raw: String
    public let date: Date?

    public init(raw: String) {
        self.raw = raw
        date = Self.parse(raw)
    }

    /// The server's format for `date`, in UTC, to the second (the web's `formatDateToDbString`).
    public init(_ date: Date) {
        let raw = Self.format(date)
        self.raw = raw
        self.date = Self.parse(raw)
    }

    public init(stringLiteral value: String) { self.init(raw: value) }

    public init(from decoder: any Decoder) throws {
        self.init(raw: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public var description: String { raw }

    public static func == (lhs: DBTimestamp, rhs: DBTimestamp) -> Bool { lhs.raw == rhs.raw }
    public func hash(into hasher: inout Hasher) { hasher.combine(raw) }

    public static func < (lhs: DBTimestamp, rhs: DBTimestamp) -> Bool {
        let left = lhs.date ?? .distantPast
        let right = rhs.date ?? .distantPast
        return left == right ? lhs.raw < rhs.raw : left < right
    }
}

// MARK: Display

extension DBTimestamp {
    /// How the web writes dates (`formatDate` in `shared/lib/formatting.ts`), always in English month names and in the
    /// given time zone (the device's by default).
    public enum Style: Hashable, Sendable {
        /// "September 14": a card's date, no year.
        case card
        /// "March 14, 2026 at 10:12 AM": the detail's captured date.
        case captured
        /// "March 14, 2026": the detail's published date.
        case published
        /// "September 2026": a month header in the list.
        case month

        public func format(_ date: Date, timeZone: TimeZone = .current) -> String {
            // en_US_POSIX pins English names and a plain "AM"/"PM" (en_US's shortened time style puts a narrow
            // no-break space before it). VerbatimFormatStyle is a value type and Foundation caches the ICU formatter
            // behind it, so building one per call costs about a microsecond.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let locale = Locale(identifier: "en_US_POSIX")
            let pattern: Date.FormatString = switch self {
            case .card:
                "\(month: .wide) \(day: .defaultDigits)"
            case .captured:
                "\(month: .wide) \(day: .defaultDigits), \(year: .defaultDigits) at \(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(dayPeriod: .standard(.abbreviated))"
            case .published:
                "\(month: .wide) \(day: .defaultDigits), \(year: .defaultDigits)"
            case .month:
                "\(month: .wide) \(year: .defaultDigits)"
            }
            return Date.VerbatimFormatStyle(format: pattern, locale: locale, timeZone: timeZone, calendar: calendar)
                .format(date)
        }
    }

    /// `date` in `style`; nil when the raw text didn't parse.
    public func text(_ style: Style, timeZone: TimeZone = .current) -> String? {
        date.map { style.format($0, timeZone: timeZone) }
    }
}

// MARK: Parsing and formatting

extension DBTimestamp {
    /// Parses `YYYY-MM-DD HH:MM:SS`, also accepting a `T` separator, a fraction of a second (dropped) and a trailing
    /// `Z`, always as UTC. Pure arithmetic on the bytes: no formatter, no calendar, no locale.
    static func parse(_ text: String) -> Date? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 19,
              bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"),
              bytes[10] == UInt8(ascii: " ") || bytes[10] == UInt8(ascii: "T"),
              bytes[13] == UInt8(ascii: ":"), bytes[16] == UInt8(ascii: ":"),
              let year = number(bytes, 0, 4), let month = number(bytes, 5, 2), let day = number(bytes, 8, 2),
              let hour = number(bytes, 11, 2), let minute = number(bytes, 14, 2), let second = number(bytes, 17, 2)
        else { return nil }
        var rest = bytes[19...]
        if rest.first == UInt8(ascii: ".") {
            rest = rest.dropFirst()
            let digits = rest.prefix { (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0) }
            guard !digits.isEmpty else { return nil }
            rest = rest.dropFirst(digits.count)
        }
        if rest.first == UInt8(ascii: "Z") { rest = rest.dropFirst() }
        guard rest.isEmpty,
              (1 ... 12).contains(month), (1 ... daysIn(month: month, year: year)).contains(day),
              (0 ... 23).contains(hour), (0 ... 59).contains(minute), (0 ... 59).contains(second)
        else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// `date` as `YYYY-MM-DD HH:MM:SS` in UTC, truncated to the second.
    static func format(_ date: Date) -> String {
        let total = Int(date.timeIntervalSince1970.rounded(.down))
        let days = Int((Double(total) / 86_400).rounded(.down))
        let secondsOfDay = total - days * 86_400
        let (year, month, day) = civilFromDays(days)
        func pad(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2)) "
            + "\(pad(secondsOfDay / 3_600, 2)):\(pad(secondsOfDay % 3_600 / 60, 2)):\(pad(secondsOfDay % 60, 2))"
    }

    private static func number(_ bytes: [UInt8], _ start: Int, _ count: Int) -> Int? {
        var value = 0
        for byte in bytes[start ..< start + count] {
            guard (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte) else { return nil }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return value
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's `days_from_civil`).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The inverse of `daysFromCivil` (Hinnant's `civil_from_days`).
    private static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}
