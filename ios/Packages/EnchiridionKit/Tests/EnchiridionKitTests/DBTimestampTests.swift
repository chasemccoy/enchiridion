@testable import EnchiridionKit
import Foundation
import Testing

@Suite struct DBTimestampTests {
    private let chicago = TimeZone(identifier: "America/Chicago")!
    private let utc = TimeZone(identifier: "UTC")!

    @Test func parsesServerFormatAsUTC() throws {
        let timestamp = DBTimestamp(raw: "2026-09-27 16:44:28")
        let date = try #require(timestamp.date)
        #expect(date.timeIntervalSince1970 == 1_790_527_468)
        #expect(DBTimestamp(raw: "1970-01-01 00:00:00").date?.timeIntervalSince1970 == 0)
        #expect(DBTimestamp(raw: "1969-12-31 23:59:59").date?.timeIntervalSince1970 == -1)
        #expect(DBTimestamp(raw: "2024-02-29 12:00:00").date?.timeIntervalSince1970 == 1_709_208_000)
    }

    @Test func agreesWithFoundationsParser() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for raw in ["2025-06-28 18:54:06", "2000-02-29 23:59:59", "2100-03-01 00:00:00", "1999-12-31 12:34:56"] {
            #expect(DBTimestamp(raw: raw).date == formatter.date(from: raw), "\(raw)")
        }
    }

    @Test(arguments: ["2026-09-27T16:44:28", "2026-09-27 16:44:28Z", "2026-09-27T16:44:28.123Z", "2026-09-27 16:44:28.5"])
    func acceptsISOVariants(raw: String) {
        #expect(DBTimestamp(raw: raw).date?.timeIntervalSince1970 == 1_790_527_468)
    }

    @Test(arguments: ["", "2026-09-27", "2026-09-27 16:44", "2026/09/27 16:44:28", "2026-13-01 00:00:00",
                      "2026-02-29 00:00:00", "2026-04-31 00:00:00", "2026-01-01 24:00:00", "2026-01-01 00:60:00",
                      "2026-01-01 00:00:00+02:00", "2026-01-01 00:00:00.", "yesterday at noon", "2026-0a-01 00:00:00"])
    func rejectsOtherText(raw: String) {
        #expect(DBTimestamp(raw: raw).date == nil)
    }

    @Test func formatsLikeTheServer() {
        #expect(DBTimestamp(Date(timeIntervalSince1970: 1_790_527_468.9)).raw == "2026-09-27 16:44:28")
        #expect(DBTimestamp(Date(timeIntervalSince1970: 0)).raw == "1970-01-01 00:00:00")
        #expect(DBTimestamp(Date(timeIntervalSince1970: -1)).raw == "1969-12-31 23:59:59")
        #expect(DBTimestamp(Date(timeIntervalSince1970: 951_782_400)).raw == "2000-02-29 00:00:00")
    }

    @Test func roundTripsArbitraryDates() {
        var seconds: Int64 = -2_208_988_800    // 1900-01-01
        while seconds < 4_102_444_800 {        // 2100-01-01
            let timestamp = DBTimestamp(Date(timeIntervalSince1970: TimeInterval(seconds)))
            #expect(timestamp.date?.timeIntervalSince1970 == TimeInterval(seconds), "\(timestamp.raw)")
            seconds += 7_777_777
        }
    }

    @Test func codableKeepsTheRawString() throws {
        let values = try JSONDecoder().decode([DBTimestamp?].self, from: Data(#"["2026-09-27 16:44:28","odd text",null]"#.utf8))
        #expect(values[0]?.date != nil)
        #expect(values[1]?.raw == "odd text")
        #expect(values[1]?.date == nil)
        #expect(values[2] == nil)
        let encoded = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        #expect(encoded == #"["2026-09-27 16:44:28","odd text",null]"#)
    }

    @Test func ordersByDate() {
        let a: DBTimestamp = "2026-01-01 00:00:00"
        let b: DBTimestamp = "2026-01-01 00:00:01"
        let c: DBTimestamp = "2026-01-01T00:00:01Z"
        let junk: DBTimestamp = "junk"
        #expect(a < b)
        #expect(!(b < a))
        #expect(junk < a)
        #expect(b != c)                                 // equality is the raw text
        #expect([b, junk, a].sorted() == [junk, a, b])
    }

    @Test func styles() {
        // 2026-03-14 15:12 UTC is 10:12 AM in Chicago (CDT began March 8).
        let date = DBTimestamp(raw: "2026-03-14 15:12:00")
        #expect(date.text(.card, timeZone: chicago) == "March 14")
        #expect(date.text(.captured, timeZone: chicago) == "March 14, 2026 at 10:12 AM")
        #expect(date.text(.published, timeZone: chicago) == "March 14, 2026")
        #expect(date.text(.month, timeZone: chicago) == "March 2026")
        #expect(DBTimestamp(raw: "nope").text(.card) == nil)
    }

    @Test func stylesUseTheLocalDay() {
        // 03:30 UTC on September 1 is still August 31 in Chicago.
        let date = DBTimestamp(raw: "2026-09-01 03:30:00")
        #expect(date.text(.card, timeZone: chicago) == "August 31")
        #expect(date.text(.month, timeZone: chicago) == "August 2026")
        #expect(date.text(.captured, timeZone: chicago) == "August 31, 2026 at 10:30 PM")
        #expect(date.text(.card, timeZone: utc) == "September 1")
        #expect(date.text(.month, timeZone: utc) == "September 2026")
    }

    @Test func midnightAndNoonReadAsTwelve() {
        #expect(DBTimestamp(raw: "2026-09-14 00:05:00").text(.captured, timeZone: utc) == "September 14, 2026 at 12:05 AM")
        #expect(DBTimestamp(raw: "2026-09-14 12:00:00").text(.captured, timeZone: utc) == "September 14, 2026 at 12:00 PM")
    }
}
