import EnchiridionKit
import Foundation
import Synchronization
import Testing
@testable import EnchiridionCore

/// The web's fix: when the open record leaves the list, open the one that took its place.
struct SelectionRuleTests {
    @Test func aSelectionStillListedStays() {
        #expect(LibraryModel.successor(of: 2, previous: [1, 2, 3], next: [2, 3]) == 2)
        #expect(LibraryModel.successor(of: 2, previous: [], next: [3, 2]) == 2)
    }

    @Test func theRecordThatTookItsIndex() {
        #expect(LibraryModel.successor(of: 2, previous: [1, 2, 3], next: [1, 3]) == 3)
        #expect(LibraryModel.successor(of: 2, previous: [1, 2, 3, 4, 5], next: [1, 5]) == 5)
        #expect(LibraryModel.successor(of: 1, previous: [1, 2, 3], next: [2, 3]) == 2)
    }

    @Test func theLastWhenNothingTookItsIndex() {
        #expect(LibraryModel.successor(of: 3, previous: [1, 2, 3], next: [1, 2]) == 2)
        #expect(LibraryModel.successor(of: 4, previous: [1, 2, 3, 4], next: [1]) == 1)
    }

    @Test func noneWhenTheListEmptied() {
        #expect(LibraryModel.successor(of: 1, previous: [1], next: []) == nil)
    }

    @Test func aSelectionNeverListedIsLeftAlone() {
        #expect(LibraryModel.successor(of: 9, previous: [1, 2], next: [1]) == 9, "opened from a link")
        #expect(LibraryModel.successor(of: nil, previous: [1, 2], next: [1]) == nil)
    }
}

/// An index load answered from before changes made here while it was out: they are replayed onto it.
struct ReplayTests {
    private let rows = [Fixture.row(1), Fixture.row(2), Fixture.row(3, created: "2026-09-01 10:00:00")]

    @Test func deletesLeaveUpdatesMergeAndCreatesInsertInOrder() {
        let replayed = LibraryModel.replay([
            .deleted(id: 1),
            .updated(Fixture.record(2, title: "Two, curated", curated: true)),
            .created(Fixture.record(10, title: "New", created: "2026-09-10 10:00:00")),
            .updated(Fixture.record(99, title: "A highlight the index hides")),
        ], onto: rows)
        #expect(replayed.map(\.id) == [2, 10, 3])
        #expect(replayed[0].isCurated)
        #expect(replayed[0].title == "Two, curated")
    }

    @Test func aRowNewerThanTheChangeWins() {
        var newer = Fixture.row(2, title: "Edited on the web")
        newer.recordUpdatedAt = "2026-09-20 10:00:00"
        let replayed = LibraryModel.replay([.updated(Fixture.record(2, title: "Older"))], onto: [newer])
        #expect(replayed.first?.title == "Edited on the web")
    }

    @Test func aCreateTheIndexAlreadyHasIsMergedNotDoubled() {
        let replayed = LibraryModel.replay([.created(Fixture.record(2, title: "Two"))], onto: rows)
        #expect(replayed.map(\.id) == [1, 2, 3])
    }
}

struct FilterTests {
    private let rows = [
        Fixture.row(1, type: .artifact), Fixture.row(2, type: .concept, curated: true),
        Fixture.row(3, type: .entity), Fixture.row(4, type: .artifact, curated: true),
    ]

    @Test func typeAndCuration() {
        #expect(LibraryModel.visible(rows, filters: .init()).map(\.id) == [1, 2, 3, 4])
        #expect(LibraryModel.visible(rows, filters: .init(type: .artifact)).map(\.id) == [1, 4])
        #expect(LibraryModel.visible(rows, filters: .init(needsCuration: true)).map(\.id) == [1, 3])
        #expect(LibraryModel.visible(rows, filters: .init(type: .artifact, needsCuration: true)).map(\.id) == [1])
        #expect(LibraryModel.visible(rows, filters: .init(type: "unknown")).isEmpty)
    }
}

struct SectionTests {
    /// October 2nd; October 1st 03:00 UTC (still September 30th in Chicago); six September rows; one undated.
    private let rows: [ListRecord] = [
        Fixture.row(1, created: "2026-10-02 12:00:00"),
        Fixture.row(2, created: "2026-10-01 03:00:00"),
    ] + (3 ... 8).map { Fixture.row($0, created: "2026-09-14 15:00:00") } + [
        Fixture.row(9, created: "yesterday"),
    ]

    @Test func groupedByLocalMonth() {
        let utc = LibraryModel.sections(rows, grouped: true, timeZone: .gmt)
        #expect(utc.map(\.title) == ["October 2026", "September 2026", "Undated"])
        #expect(utc.map { $0.records.map(\.id) } == [[1, 2], [3, 4, 5, 6, 7, 8], [9]])

        let chicago = LibraryModel.sections(rows, grouped: true, timeZone: TimeZone(identifier: "America/Chicago")!)
        #expect(chicago.map(\.title) == ["October 2026", "September 2026", "Undated"])
        #expect(chicago[0].records.map(\.id) == [1])
        #expect(chicago[1].records.map(\.id) == [2, 3, 4, 5, 6, 7, 8])
    }

    @Test func theCountShowsPastFour() {
        let sections = LibraryModel.sections(rows, grouped: true, timeZone: .gmt)
        #expect(sections[0].heading == "October 2026")
        #expect(sections[0].countText == nil)
        #expect(sections[1].heading == "September 2026 (6)")
        #expect(sections[1].countText == "(6)")
    }

    @Test func aMonthSplitBySortingStaysOneGroup() {
        let rows = [Fixture.row(1, created: "2026-09-02 12:00:00"), Fixture.row(2, created: "2026-08-02 12:00:00"),
                    Fixture.row(3, created: "2026-09-01 12:00:00")]
        let sections = LibraryModel.sections(rows, grouped: true, timeZone: .gmt)
        #expect(sections.map { $0.records.map(\.id) } == [[1, 3], [2]])
    }

    @Test func ungroupedIsOneUntitledSection() {
        let sections = LibraryModel.sections(rows, grouped: false, timeZone: .gmt)
        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
        #expect(sections[0].heading == nil)
        #expect(sections[0].records.count == rows.count)
        #expect(LibraryModel.sections([], grouped: true, timeZone: .gmt).isEmpty)
        #expect(LibraryModel.sections([], grouped: false, timeZone: .gmt).isEmpty)
    }
}

@MainActor
struct LibraryModelTests {
    private let index = [
        Fixture.row(1, title: "One"), Fixture.row(2, title: "Two"), Fixture.row(3, title: "Three"),
    ]

    private func loaded(_ rows: [ListRecord]? = nil, clock: any Clock<Duration> = ContinuousClock(),
                        timings: Timings = .immediate,
                        handler: @escaping StubTransport.Handler = { _ in throw URLError(.timedOut) })
        async -> (LibraryModel, StubTransport) {
        let rows = rows ?? index
        let transport = StubTransport { request in
            request.route == "POST /records" ? .json(rows) : try handler(request)
        }
        let library = LibraryModel(environment: .test(transport, clock: clock, timings: timings))
        await library.load()
        return (library, transport)
    }

    @Test func loadsTheIndexAsTheWebDoes() async throws {
        let (library, transport) = await loaded()
        #expect(library.state == .loaded)
        #expect(library.records.map(\.id) == [1, 2, 3])
        #expect(library.visibleRecords.map(\.id) == [1, 2, 3])
        #expect(library.sections.map(\.title) == ["September 2026"])
        #expect(library.countText == "3 records")

        let request = try #require(await transport.requests.first)
        #expect(request.route == "POST /records")
        #expect(request.headers["X-Enchiridion-Client"] == "ios/0.1 app")
        let body = request.json()
        #expect(body["limit"] as? Int == 100_000)
        #expect((body["filters"] as? [String: Any])?["hideUntitledChildren"] as? Bool == true)
        let order = body["orderBy"] as? [[String: String]]
        #expect(order == [["field": "recordCreatedAt", "direction": "desc"], ["field": "slug", "direction": "asc"]])

        await library.load()
        #expect(await transport.routes.count == 1, "a loaded index isn't fetched again on appear")
        await library.refresh()
        #expect(await transport.routes.count == 2)
    }

    @Test func aRefusedDeviceIsNamed() async {
        let transport = StubTransport { _ in
            .raw(#"{"error":{"code":"unauthorized","message":"x"},"message":"x","device":{"id":"n1","name":"vern"}}"#,
                 status: 401)
        }
        let library = LibraryModel(environment: .test(transport))
        #expect(library.countText == nil, "nothing to count before a load")
        await library.load()
        #expect(library.state == .failed(.unauthorized(device: Device(id: "n1", name: "vern"))))
        #expect(library.records.isEmpty)
        #expect(library.countText == nil, "not \"0 records\" above the not-allowed state")
    }

    @Test func anEmptyLibraryCountsZero() async {
        let (library, _) = await loaded([])
        #expect(library.countText == "0 records")
    }

    @Test func aFailedRefreshKeepsTheRows() async {
        let (library, transport) = await loaded()
        await transport.respond { _ in throw URLError(.timedOut) }
        await library.refresh()
        #expect(library.state == .failed(.unreachable))
        #expect(library.records.count == 3)
        #expect(library.visibleRecords.count == 3)
    }

    @Test func filtersNarrowTheListAndTheCount() async {
        let rows = [Fixture.row(1, type: .concept), Fixture.row(2), Fixture.row(3, curated: true)]
        let (library, _) = await loaded(rows)
        library.filters.type = .artifact
        #expect(library.visibleRecords.map(\.id) == [2, 3])
        #expect(library.countText == "2 of 3 records")
        library.filters.needsCuration = true
        #expect(library.visibleRecords.map(\.id) == [2])
        library.filters = .init()
        #expect(library.countText == "3 records")
    }

    @Test func curatingUnderNeedsCurationMovesTheSelection() async throws {
        let (library, transport) = await loaded(handler: { request in
            #expect(request.route == "PUT /record")
            return .json(Fixture.record(2, title: "Two", curated: true))
        })
        library.filters.needsCuration = true
        library.selectedID = 2

        #expect(await library.setCurated(id: 2, true))
        #expect(library.visibleRecords.map(\.id) == [1, 3])
        #expect(library.selectedID == 3, "the record that took its place")
        #expect(library.row(id: 2)?.isCurated == true)
        #expect(library.workingIDs.isEmpty)

        let body = try #require(await transport.requests.last).json()
        #expect(Set(body.keys) == ["id", "slug", "isCurated"], "nothing stale is written back")
        #expect(body["id"] as? Int == 2)
        #expect(body["slug"] as? String == "record-2")
        #expect(body["isCurated"] as? Bool == true)
    }

    @Test func aFailedCuratePutsTheRowBack() async {
        let (library, transport) = await loaded(handler: { _ in
            .raw(#"{"message":"Failed query: update"}"#, status: 500)
        })
        library.filters.needsCuration = true
        #expect(await library.setCurated(id: 2, true) == false)
        #expect(library.row(id: 2)?.isCurated == false)
        #expect(library.visibleRecords.map(\.id) == [1, 2, 3])
        #expect(library.actionError == .server(status: 500, message: "Failed query: update"))
        #expect(await transport.routes == ["POST /records", "PUT /record"], "a refusal isn't read back")
        library.clearActionError()
        #expect(library.actionError == nil)
    }

    /// A library over rows 1 to 3 whose curate PUT reaches the server (when `lands`) and then loses its answer;
    /// `GET /record/2` answers what the server holds, or fails too when `readsFail`.
    private func lostCurate(lands: Bool, readsFail: Bool = false) async -> (LibraryModel, StubTransport) {
        let stored = Mutex(Fixture.record(2, title: "Two"))
        return await loaded(handler: { request in
            switch request.route {
            case "PUT /record":
                if lands { stored.withLock { $0.isCurated = true } }
                throw URLError(.networkConnectionLost)
            case "GET /record/2":
                if readsFail { throw URLError(.timedOut) }
                return .json(RecordDetail(record: stored.withLock { $0 }))
            default:
                return .notFound
            }
        })
    }

    @Test func aCurateWhoseAnswerWasLostButLandedStays() async {
        let (library, transport) = await lostCurate(lands: true)
        library.filters.needsCuration = true
        library.selectedID = 2
        #expect(await library.setCurated(id: 2, true))
        #expect(library.row(id: 2)?.isCurated == true, "the server holds it, so the row isn't put back")
        #expect(library.visibleRecords.map(\.id) == [1, 3])
        #expect(library.selectedID == 3)
        #expect(library.actionError == nil)
        #expect(await transport.routes == ["POST /records", "PUT /record", "GET /record/2"])
    }

    @Test func aLostCurateTheRecordDoesNotHoldIsPutBack() async {
        let (library, _) = await lostCurate(lands: false)
        library.filters.needsCuration = true
        #expect(await library.setCurated(id: 2, true) == false)
        #expect(library.row(id: 2)?.isCurated == false)
        #expect(library.visibleRecords.map(\.id) == [1, 2, 3])
        #expect(library.actionError == .unreachable)
    }

    @Test func aLostCurateThatCannotBeCheckedIsPutBack() async {
        // The rows keep to what the server last confirmed; curating again is safe, since it sets a value.
        let (library, _) = await lostCurate(lands: true, readsFail: true)
        #expect(await library.setCurated(id: 2, true) == false)
        #expect(library.row(id: 2)?.isCurated == false)
        #expect(library.actionError == .unreachable)
        #expect(library.workingIDs.isEmpty)
    }

    @Test func aLostCurateOfARecordDeletedElsewhereDropsItsRow() async {
        let (library, _) = await loaded(handler: { request in
            if request.route == "PUT /record" { throw URLError(.timedOut) }
            return .notFound
        })
        #expect(await library.setCurated(id: 2, true) == false)
        #expect(library.row(id: 2) == nil)
        #expect(library.actionError == .notFound)
    }

    @Test func deletingTakesMediaFirstAndMovesTheSelection() async {
        let rows = [Fixture.row(1, media: [Fixture.media(7, recordID: 1)]), Fixture.row(2), Fixture.row(3)]
        let (library, transport) = await loaded(rows, handler: { request in
            switch request.route {
            case "DELETE /media/record/1": .json([Fixture.media(7, recordID: 1)])
            case "DELETE /media/record/2": .json([Media]())
            case "DELETE /record/1": .json([Fixture.record(1)])
            case "DELETE /record/2": .json([Fixture.record(2)])
            default: .notFound
            }
        })
        library.selectedID = 1

        #expect(await library.delete(id: 1))
        #expect(await transport.routes.suffix(2) == ["DELETE /media/record/1", "DELETE /record/1"])
        #expect(library.records.map(\.id) == [2, 3])
        #expect(library.selectedID == 2)

        // The row shows no media, but it may have gained some on the web since it loaded: ask anyway.
        #expect(await library.delete(id: 2))
        #expect(await transport.routes.suffix(2) == ["DELETE /media/record/2", "DELETE /record/2"])
        #expect(await transport.routes.count == 5)
        #expect(library.selectedID == 3)
    }

    @Test func curatingARecordDeletedElsewhereDropsItsRow() async {
        let (library, transport) = await loaded(handler: { _ in
            .raw(#"{"error":{"code":"not_found","message":"Record 2 doesn't exist (anymore)"},"message":"x"}"#,
                 status: 404)
        })
        library.selectedID = 2
        #expect(await library.setCurated(id: 2, true) == false)
        #expect(library.row(id: 2) == nil, "gone, not reverted")
        #expect(library.records.map(\.id) == [1, 3])
        #expect(library.selectedID == 3)
        #expect(library.actionError == .notFound)
        #expect(await transport.routes.filter { $0 == "PUT /record" }.count == 1)
    }

    @Test func aRowWithADeleteInFlightTakesNoCurate() async throws {
        let stub = StubTransport { request in
            switch request.route {
            case "POST /records": .json([Fixture.row(1), Fixture.row(2)])
            case "DELETE /media/record/2": .json([Media]())
            case "DELETE /record/2": .json([Fixture.record(2)])
            default: .notFound
            }
        }
        let transport = HoldingTransport(stub)
        let library = LibraryModel(environment: .test(transport))
        await library.load()
        await transport.hold { $0.route == "DELETE /media/record/2" }
        let deleting = Task { await library.delete(id: 2) }
        await transport.waitUntilHeld()
        #expect(library.workingIDs == [2])
        #expect(await library.setCurated(id: 2, true) == false)
        #expect(await library.delete(id: 2) == false)
        await transport.release()
        #expect(await deleting.value)
        #expect(await stub.routes == ["POST /records", "DELETE /media/record/2", "DELETE /record/2"],
                "no curate PUT for a record on its way out")
    }

    @Test func changesMadeWhileTheIndexLoadsSurviveIt() async {
        let stub = StubTransport { request in
            switch request.route {
            // The server answers the load from the rows as they are when it arrives.
            case "POST /records": .json([Fixture.row(1), Fixture.row(2), Fixture.row(3)])
            case "DELETE /media/record/1": .json([Media]())
            case "DELETE /record/1": .json([Fixture.record(1)])
            case "PUT /record": .json(Fixture.record(2, curated: true))
            default: .notFound
            }
        }
        let transport = HoldingTransport(stub)
        let library = LibraryModel(environment: .test(transport))
        await library.load()
        library.filters.needsCuration = true
        await transport.hold { $0.route == "POST /records" }
        let refreshing = Task { await library.refresh() }
        await transport.waitUntilHeld()

        #expect(await library.delete(id: 1))
        #expect(await library.setCurated(id: 2, true))
        library.apply(.created(Fixture.record(10, title: "New", created: "2026-10-11 22:00:00")))
        library.selectedID = 10
        await transport.release()
        await refreshing.value

        #expect(library.records.map(\.id) == [10, 2, 3], "the deleted row stays gone; the new one stays")
        #expect(library.row(id: 2)?.isCurated == true, "the curate isn't undone")
        #expect(library.visibleRecords.map(\.id) == [10, 3])
        #expect(library.selectedID == 10)
    }

    @Test func aCurateInFlightOutlastsALoad() async {
        let stub = StubTransport { request in
            switch request.route {
            case "POST /records": .json([Fixture.row(1), Fixture.row(2)])
            case "PUT /record": .json(Fixture.record(2, curated: true))
            default: .notFound
            }
        }
        let transport = HoldingTransport(stub) { $0.route == "PUT /record" }
        let library = LibraryModel(environment: .test(transport))
        await library.load()
        let curating = Task { await library.setCurated(id: 2, true) }
        await transport.waitUntilHeld()
        await library.refresh()
        #expect(library.row(id: 2)?.isCurated == true, "the switch doesn't flick back while the curate is out")
        await transport.release()
        #expect(await curating.value)
        #expect(library.row(id: 2)?.isCurated == true)
    }

    @Test func comingBackReloadsOnlyWhenTheNewestRecordIsMissing() async throws {
        let rows = Mutex([Fixture.row(1, created: "2026-09-02 10:00:00"), Fixture.row(2)])
        let transport = StubTransport { request in
            guard request.route == "POST /records" else { return .notFound }
            let all = rows.withLock { $0 }
            return .json(request.json()["limit"] as? Int == 1 ? Array(all.prefix(1)) : all)
        }
        let library = LibraryModel(environment: .test(transport))
        await library.refreshIfNewer()
        #expect(await transport.routes.isEmpty, "nothing before the index has loaded")
        await library.load()

        await library.refreshIfNewer()
        #expect(await transport.routes == ["POST /records", "POST /records"])
        #expect(try #require(await transport.requests.last).json()["limit"] as? Int == 1)

        // Shared from Safari meanwhile.
        rows.withLock { $0.insert(Fixture.row(3, created: "2026-10-11 22:00:00"), at: 0) }
        await library.refreshIfNewer()
        #expect(await transport.routes.count == 4)
        #expect(library.records.map(\.id) == [3, 1, 2])
    }

    @Test func aFailedDeleteKeepsTheRow() async {
        let (library, _) = await loaded(handler: { _ in throw URLError(.notConnectedToInternet) })
        #expect(await library.delete(id: 2) == false)
        #expect(library.records.count == 3)
        #expect(library.actionError == .offline)
    }

    @Test func savesMergeIntoRowsAndNewRecordsAreInserted() async {
        let tagged = ListRecord.OutgoingLink(predicate: .taggedWith,
                                             target: RecordRef(id: 40, title: "swift", slug: "swift"))
        var first = Fixture.row(1, title: "One", media: [Fixture.media(7, recordID: 1)])
        first.outgoingLinks = [tagged]
        let (library, _) = await loaded([first, Fixture.row(2, created: "2026-09-01 10:00:00")])

        library.apply(saved: Fixture.record(1, title: "One, renamed", url: "https://example.com"))
        let merged = library.row(id: 1)
        #expect(merged?.title == "One, renamed")
        #expect(merged?.url == "https://example.com")
        #expect(merged?.media.count == 1, "a save keeps the row's media")
        #expect(merged?.outgoingLinks == [tagged], "and its links")

        library.apply(.created(Fixture.record(10, title: "New", created: "2026-10-11 22:00:00")))
        library.apply(.created(Fixture.record(11, title: "Middle", created: "2026-09-10 10:00:00")))
        #expect(library.records.map(\.id) == [10, 1, 11, 2], "in index order")
        #expect(library.sections.map(\.title) == ["October 2026", "September 2026"])

        library.apply(.updated(Fixture.record(99, title: "A highlight")))
        #expect(library.row(id: 99) == nil, "an update to a record the index hides isn't inserted")

        library.selectedID = 10
        library.apply(.deleted(id: 10))
        #expect(library.records.map(\.id) == [1, 11, 2])
        #expect(library.selectedID == 1)
    }

    @Test func removingASelectionNeverListedClearsIt() async {
        let (library, _) = await loaded()
        library.filters.type = .concept
        library.selectedID = 2
        library.remove(id: 2)
        #expect(library.selectedID == nil)
    }

    @Test func searchWaitsForTypingToPause() async throws {
        let clock = TestClock()
        let results = [Fixture.row(3, title: "Three"), Fixture.row(1, title: "One", curated: true)]
        let (library, transport) = await loaded(clock: clock, timings: .standard, handler: { request in
            #expect(request.route == "GET /search/hybrid")
            return .json(results)
        })
        library.selectedID = 2

        library.query = "o"
        await clock.waitForSleepers(1)
        library.query = "on"
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(249))
        #expect(!library.isSearching)
        #expect(await transport.routes == ["POST /records"])

        clock.advance(by: .milliseconds(1))
        await library.settled()
        let search = try #require(await transport.requests.last)
        #expect(await transport.routes.count == 2, "one search for the pause, none per keystroke")
        #expect(search.query == ["q": "on", "limit": "100"])

        #expect(library.isSearching)
        #expect(library.activeQuery == "on")
        #expect(library.visibleRecords.map(\.id) == [3, 1], "relevance order")
        #expect(library.sections.count == 1)
        #expect(library.sections.first?.title == nil, "no month headers while searching")
        #expect(library.countText == "2 results")
        #expect(library.selectedID == nil, "the selection left with the index")

        library.filters.needsCuration = true
        #expect(library.visibleRecords.map(\.id) == [3])
        #expect(library.countText == "1 of 2 results")
        library.filters = .init()

        library.query = "on "
        #expect(clock.sleeperCount == 0, "the same text, trimmed, asks nothing")

        library.query = ""
        #expect(!library.isSearching)
        #expect(library.visibleRecords.map(\.id) == [1, 2, 3])
        #expect(library.sections.first?.title == "September 2026")
        #expect(library.searchResults == nil)
        #expect(await transport.routes.count == 2)
    }

    @Test func aFailedSearchSaysSo() async {
        let (library, _) = await loaded(handler: { _ in .raw(#"{"error":"Search failed"}"#, status: 500) })
        library.query = "tiny internets"
        await library.settled()
        #expect(library.searchState == .failed(.server(status: 500, message: "Search failed")))
        #expect(library.countText == "Search failed. Try again.")
        #expect(library.visibleRecords.isEmpty)
    }

    @Test func refreshRunsTheSearchAgain() async {
        let (library, transport) = await loaded(handler: { _ in .json([Fixture.row(2)]) })
        library.query = "two"
        await library.settled()
        await library.refresh()
        #expect(await transport.routes
            == ["POST /records", "GET /search/hybrid", "POST /records", "GET /search/hybrid"])
        #expect(library.visibleRecords.map(\.id) == [2])
    }

    @Test func refreshSearchesWhatTheFieldHoldsNow() async {
        let clock = TestClock()
        let stub = StubTransport { request in
            switch request.route {
            case "POST /records": .json([Fixture.row(1), Fixture.row(2)])
            case "GET /search/hybrid": .json(request.query["q"] == "abcd" ? [Fixture.row(2)] : [Fixture.row(1)])
            default: .notFound
            }
        }
        let transport = HoldingTransport(stub)
        let library = LibraryModel(environment: .test(transport, clock: clock, timings: .standard))
        await library.load()
        library.query = "abc"
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(250))
        await library.settled()
        #expect(library.activeQuery == "abc")

        await transport.hold { $0.route == "POST /records" }
        let refreshing = Task { await library.refresh() }
        await transport.waitUntilHeld()
        library.query = "abcd" // typed while the index reloads; its debounce hasn't passed
        await clock.waitForSleepers(1)
        await transport.release()
        await refreshing.value

        #expect(library.activeQuery == "abcd")
        #expect(library.visibleRecords.map(\.id) == [2])
        #expect(await stub.requests.compactMap { $0.query["q"] } == ["abc", "abcd"])
    }

    @Test func clearingTheSearchLeavesAResultTheIndexHidesOpen() async {
        // Hybrid search finds untitled highlights, which the index hides.
        let (library, _) = await loaded(handler: { _ in .json([Fixture.row(2), Fixture.row(3), Fixture.row(99)]) })
        library.query = "gibson"
        await library.settled()
        library.selectedID = 99
        library.query = ""
        #expect(library.visibleRecords.map(\.id) == [1, 2, 3])
        #expect(library.selectedID == 99, "not the index's third record: another list, another position")
    }

    @Test func refiningTheSearchKeepsTheSelection() async {
        let (library, _) = await loaded(handler: { request in
            .json(request.query["q"] == "ab" ? [Fixture.row(3), Fixture.row(1)] : [Fixture.row(1), Fixture.row(2),
                                                                                  Fixture.row(3)])
        })
        library.query = "a"
        await library.settled()
        library.selectedID = 2
        library.query = "ab"
        await library.settled()
        #expect(library.visibleRecords.map(\.id) == [3, 1])
        #expect(library.selectedID == 2)
    }

    @Test func theSameSearchAgainMovesASelectionThatLeft() async {
        let searches = Mutex(0)
        let (library, _) = await loaded(handler: { _ in
            let first = searches.withLock { count in
                count += 1
                return count == 1
            }
            return .json(first ? [Fixture.row(1), Fixture.row(2), Fixture.row(3)] : [Fixture.row(1), Fixture.row(3)])
        })
        library.query = "a"
        await library.settled()
        library.selectedID = 2
        await library.refresh()
        #expect(library.visibleRecords.map(\.id) == [1, 3])
        #expect(library.selectedID == 3, "the same list lost it: the record that took its place")
    }

    @Test func changesMadeWhileASearchIsOutSurviveItsAnswer() async {
        let stub = StubTransport { request in
            switch request.route {
            case "POST /records": .json([Fixture.row(1), Fixture.row(2), Fixture.row(3)])
            // The server reads the rows when the search arrives: before the delete and the curate below.
            case "GET /search/hybrid": .json([Fixture.row(1), Fixture.row(2), Fixture.row(3)])
            case "DELETE /media/record/1": .json([Media]())
            case "DELETE /record/1": .json([Fixture.record(1)])
            case "PUT /record": .json(Fixture.record(2, curated: true))
            default: .notFound
            }
        }
        let transport = HoldingTransport(stub)
        let library = LibraryModel(environment: .test(transport))
        await library.load()
        library.query = "gibson"
        await library.settled()
        library.filters.needsCuration = true
        #expect(library.visibleRecords.map(\.id) == [1, 2, 3])

        // Pull to refresh runs the same search again; its answer is held while a delete and a curate land.
        await transport.hold { $0.route == "GET /search/hybrid" }
        let refreshing = Task { await library.refresh() }
        await transport.waitUntilHeld()
        #expect(await library.delete(id: 1))
        #expect(await library.setCurated(id: 2, true))
        library.apply(.created(Fixture.record(10, title: "New")))
        #expect(library.visibleRecords.map(\.id) == [3])
        await transport.release()
        await refreshing.value

        #expect(library.visibleRecords.map(\.id) == [3], "the deleted result stays gone; the curated one stays out")
        #expect(library.searchResults?.map(\.id) == [2, 3], "a new record isn't ranked into the results")
        #expect(library.searchResults?.first?.isCurated == true)
        #expect(library.row(id: 1) == nil)
    }

    @Test func aDeleteWhileARefinedSearchIsOutStaysGone() async {
        let stub = StubTransport { request in
            switch request.route {
            case "POST /records": .json([Fixture.row(1), Fixture.row(2), Fixture.row(3)])
            case "GET /search/hybrid": .json([Fixture.row(1), Fixture.row(2), Fixture.row(3)])
            case "DELETE /media/record/2": .json([Media]())
            case "DELETE /record/2": .json([Fixture.record(2)])
            default: .notFound
            }
        }
        let transport = HoldingTransport(stub)
        let library = LibraryModel(environment: .test(transport))
        await library.load()
        library.query = "gib"
        await library.settled()
        await transport.hold { $0.route == "GET /search/hybrid" }
        library.query = "gibson"
        await transport.waitUntilHeld()
        #expect(await library.delete(id: 2))
        await transport.release()
        await library.settled()
        #expect(library.activeQuery == "gibson")
        #expect(library.visibleRecords.map(\.id) == [1, 3])
        #expect(library.row(id: 2) == nil)
    }

    @Test func aDetailThatFindsItsRecordDeletedElsewhereClosesAndTheLibrarySaysSo() async throws {
        let (library, _) = await loaded(handler: { request in
            switch request.route {
            case "GET /record/2": .json(RecordDetail(record: Fixture.record(2)))
            case "GET /record/2/links": .json(LinksBundle(id: 2))
            default: .raw(#"{"error":{"code":"not_found","message":"x"},"message":"x"}"#, status: 404)
            }
        })
        library.selectedID = 2
        let detail = library.detailModel(id: 2)
        await detail.load()

        // Its editor keeps the error and the text up; the row leaves once the editor closes, without an alert.
        let editor = try #require(detail.makeEditor())
        editor.draft.notes = "Too late"
        #expect(await editor.save() == nil)
        #expect(library.row(id: 2) != nil)
        #expect(!detail.isDeleted)
        editor.close()
        #expect(library.row(id: 2) == nil)
        #expect(detail.isDeleted)
        #expect(library.actionError == nil, "the editor said it")

        // The Curated switch (the index still listed it): the detail closes at once, so the library's alert says it.
        await library.refresh()
        library.selectedID = 2
        let again = library.detailModel(id: 2)
        await again.load()
        #expect(await again.setCurated(true) == false)
        #expect(again.isDeleted)
        #expect(again.actionError == nil)
        #expect(library.row(id: 2) == nil)
        #expect(library.selectedID == 3)
        #expect(library.actionError == .notFound)
    }

    @Test func aDetailWhoseLoadFindsItsRecordGoneDropsTheRow() async {
        // Deleted on the web since the index loaded: opening its row answers 404.
        let (library, _) = await loaded(handler: { request in
            request.route == "GET /record/2/links" ? .raw("") : .notFound
        })
        library.selectedID = 2
        let detail = library.detailModel(id: 2)
        await detail.load()
        #expect(detail.isDeleted, "the screen closes rather than offer a Retry that can't work")
        #expect(library.row(id: 2) == nil)
        #expect(library.selectedID == 3)
        #expect(library.actionError == .notFound)
    }

    @Test func anEditorFromADetailThatWentAwayStillReachesTheRows() async throws {
        let (library, _) = await loaded(handler: { request in
            switch request.route {
            case "GET /record/2": .json(RecordDetail(record: Fixture.record(2, title: "Two")))
            case "GET /record/2/links": .json(LinksBundle(id: 2))
            case "PUT /record": .json(Fixture.record(2, title: "Second"))
            default: .notFound
            }
        })
        library.selectedID = 2
        var detail: RecordDetailModel? = library.detailModel(id: 2)
        await detail?.load()
        let editor = try #require(detail?.makeEditor())
        // A reload moved the selection and closed the detail; the editor, presented by the library screen, stayed.
        detail = nil
        editor.draft.title = "Second"
        #expect(await editor.save() != nil)
        #expect(library.row(id: 2)?.title == "Second")
    }

    @Test func detailChangesReachTheRows() async {
        let (library, _) = await loaded(handler: { request in
            switch request.route {
            case "PUT /record": .json(Fixture.record(2, title: "Two", curated: true))
            default: .notFound
            }
        })
        library.filters.needsCuration = true
        library.selectedID = 2
        let detail = library.detailModel(id: 2)
        detail.apply(.updated(Fixture.record(2, title: "Two", curated: true)))
        #expect(library.row(id: 2)?.isCurated == true)
        #expect(library.selectedID == 3)
    }
}
