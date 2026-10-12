import EnchiridionKit
import Foundation
import Synchronization
import Testing
@testable import EnchiridionCore

/// Collects what a model reports.
@MainActor
final class ChangeLog {
    private(set) var changes: [RecordChange] = []

    var handler: RecordChangeHandler { { [weak self] in self?.changes.append($0) } }
}

struct LinkGroupTests {
    /// Record 5's links: it was created by Ada, is tagged and contained, relates to records both ways, is quoted by an
    /// untitled highlight, and is the creator of record 12.
    static let bundle = LinksBundle(
        id: 5,
        outgoingLinks: [
            .init(link: Fixture.link(1, from: 5, to: 7, .createdBy), target: .init(title: "Ada", slug: "ada")),
            .init(link: Fixture.link(2, from: 5, to: 8, .taggedWith), target: .init(title: "swift", slug: "swift")),
            .init(link: Fixture.link(3, from: 5, to: 14, .relatedTo), target: .init(title: "Kin", slug: "kin")),
            .init(link: Fixture.link(4, from: 5, to: 9, .containedBy), target: .init(title: "Book", slug: "book")),
        ],
        incomingLinks: [
            .init(link: Fixture.link(5, from: 11, to: 5, .quotes),
                  source: .init(title: nil, slug: "note-1a2b3c4d", content: "  A highlighted line.  ")),
            .init(link: Fixture.link(6, from: 12, to: 5, .createdBy), source: .init(title: "Work", slug: "work")),
            .init(link: Fixture.link(7, from: 13, to: 5, .relatedTo), source: .init(title: "Cousin", slug: "cousin")),
        ]
    )

    @Test func groupedByHowEachLinkReadsFromHere() {
        let groups = RecordDetailModel.linkGroups(Self.bundle)
        #expect(groups.map(\.name) == ["created by", "tagged with", "related to", "contained by", "quoted in",
                                       "creator of"])
        #expect(groups.map(\.label) == ["Created by", "Tagged with", "Related to", "Contained by", "Quoted in",
                                        "Creator of"], "capitalized as the web shows them")
        #expect(groups.map { $0.links.map(\.recordID) } == [[7], [8], [14, 13], [9], [11], [12]])
        let related = groups[2].links
        #expect(related.map(\.direction) == [.outgoing, .incoming])
        #expect(Set(groups.flatMap(\.links).map(\.id)).count == 7, "ids are unique")
    }

    @Test func anUntitledSourceShowsItsContent() {
        let quoted = RecordDetailModel.linkGroups(Self.bundle)[4].links[0]
        #expect(quoted.displayTitle == "A highlighted line.")
        #expect(quoted.title == nil)
        let bare = LinkedRecord(linkID: 1, direction: .outgoing, predicate: .about, recordID: 2, title: " ", slug: "x")
        #expect(bare.displayTitle == "x")
    }

    @Test func noLinksNoGroups() {
        #expect(RecordDetailModel.linkGroups(LinksBundle(id: 5)).isEmpty)
    }
}

@MainActor
struct RecordDetailModelTests {
    private nonisolated static let record = Fixture.record(5, slug: "tiny-internets", title: "Tiny internets",
                                               url: "https://example.com/tiny")
    private nonisolated static let detail = RecordDetail(
        record: record,
        outgoingLinks: [.init(predicate: .createdBy, target: Fixture.record(7, slug: "ada", title: "Ada"))],
        media: [Fixture.media(51, recordID: 5)]
    )

    private func model(detail: RecordDetail = detail, log: ChangeLog? = nil,
                       handler: @escaping StubTransport.Handler = { _ in .notFound })
        -> (RecordDetailModel, StubTransport) {
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/5": .json(detail)
            case "GET /record/5/links": .json(LinkGroupTests.bundle)
            default: try handler(request)
            }
        }
        return (RecordDetailModel(id: 5, environment: .test(transport), onChange: log?.handler), transport)
    }

    @Test func loadsTheRecordAndItsLinks() async {
        let (model, transport) = model()
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.record?.title == "Tiny internets")
        #expect(model.detail?.creator?.title == "Ada")
        #expect(model.linkGroups.count == 6)
        await model.settled()
        let loads = { await transport.routes.filter { $0 != "GET /record/5/similar" } }
        #expect(Set(await loads()) == ["GET /record/5", "GET /record/5/links"])
        #expect(await transport.routes.contains("GET /record/5/similar"), "suggestions load beside it")

        await model.load()
        #expect(await loads().count == 2, "loaded once")
        await model.refresh()
        #expect(await loads().count == 4)
    }

    @Test func aMissingRecord() async {
        let transport = StubTransport { request in
            request.route == "GET /record/5/links" ? .raw("") : .notFound
        }
        let log = ChangeLog()
        let model = RecordDetailModel(id: 5, environment: .test(transport), onChange: log.handler)
        await model.load()
        #expect(model.state == .failed(.notFound))
        #expect(model.detail == nil)
        // Deleted elsewhere (a row the phone still lists): Retry could never bring it back, so it's reported gone.
        #expect(model.isDeleted)
        #expect(log.changes == [.vanished(id: 5)])
    }

    @Test func aRefreshAnsweredNotFoundReportsTheRecordGoneOnce() async {
        let gone = Mutex(false)
        let transport = StubTransport { request in
            if gone.withLock({ $0 }) { return request.route == "GET /record/5/links" ? .raw("") : .notFound }
            switch request.route {
            case "GET /record/5": return .json(Self.detail)
            case "GET /record/5/links": return .json(LinkGroupTests.bundle)
            default: return .notFound
            }
        }
        let log = ChangeLog()
        let model = RecordDetailModel(id: 5, environment: .test(transport), onChange: log.handler)
        await model.load()
        #expect(!model.isDeleted)
        gone.withLock { $0 = true }
        await model.refresh()
        #expect(model.isDeleted)
        #expect(log.changes == [.vanished(id: 5)])
        await model.refresh()
        #expect(log.changes == [.vanished(id: 5)], "once")
    }

    @Test func aFailedLoadThatIsNotNotFoundKeepsTheRecord() async {
        let transport = StubTransport { _ in throw URLError(.timedOut) }
        let log = ChangeLog()
        let model = RecordDetailModel(id: 5, environment: .test(transport), onChange: log.handler)
        await model.load()
        #expect(model.state == .failed(.unreachable))
        #expect(!model.isDeleted)
        #expect(log.changes.isEmpty)
    }

    /// A detail on record 5 whose curate PUT reaches the server (when `lands`) and then loses its answer; reads
    /// answer from what the server holds, or fail too when `readsFail`.
    private func lostCurate(lands: Bool, readsFail: Bool = false, log: ChangeLog)
        -> (RecordDetailModel, StubTransport) {
        let stored = Mutex(Self.record)
        let reading = Mutex(false)
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/5":
                if reading.withLock({ $0 }), readsFail { throw URLError(.timedOut) }
                return .json(RecordDetail(record: stored.withLock { $0 }))
            case "GET /record/5/links":
                return .json(LinkGroupTests.bundle)
            case "PUT /record":
                if lands { stored.withLock { $0.isCurated = true } }
                reading.withLock { $0 = true }
                throw URLError(.networkConnectionLost)
            default:
                return .notFound
            }
        }
        return (RecordDetailModel(id: 5, environment: .test(transport), onChange: log.handler), transport)
    }

    @Test func aCurateWhoseAnswerWasLostButLandedStays() async {
        let log = ChangeLog()
        let (model, transport) = lostCurate(lands: true, log: log)
        await model.load()
        #expect(await model.setCurated(true))
        #expect(model.record?.isCurated == true, "the server holds it, so the switch stays")
        #expect(model.actionError == nil)
        #expect(log.changes.count == 1)
        #expect(await transport.routes.suffix(2) == ["PUT /record", "GET /record/5"], "read back")
    }

    @Test func aLostCurateTheRecordDoesNotHoldMovesBack() async {
        let log = ChangeLog()
        let (model, _) = lostCurate(lands: false, log: log)
        await model.load()
        #expect(await model.setCurated(true) == false)
        #expect(model.record?.isCurated == false)
        #expect(model.actionError == .unreachable)
        #expect(log.changes.isEmpty)
    }

    @Test func aLostCurateThatCannotBeCheckedMovesBack() async {
        // The screen keeps to what the server last confirmed; curating again is safe, since it sets a value.
        let log = ChangeLog()
        let (model, _) = lostCurate(lands: true, readsFail: true, log: log)
        await model.load()
        #expect(await model.setCurated(true) == false)
        #expect(model.record?.isCurated == false)
        #expect(model.actionError == .unreachable)
    }

    @Test func curatingSendsOnlyTheFlag() async throws {
        let log = ChangeLog()
        var stored = Self.record
        stored.isCurated = true
        let curated = stored
        let (model, transport) = model(log: log, handler: { _ in .json(curated) })
        await model.load()

        #expect(await model.setCurated(true))
        #expect(model.record?.isCurated == true)
        #expect(log.changes == [.updated(curated)])
        let body = try #require(await transport.requests.last).json()
        #expect(Set(body.keys) == ["id", "slug", "isCurated"])
        #expect(body["slug"] as? String == "tiny-internets")
    }

    @Test func aFailedCurateMovesTheSwitchBack() async {
        let log = ChangeLog()
        let (model, _) = model(log: log, handler: { _ in throw URLError(.cannotFindHost) })
        await model.load()
        #expect(await model.setCurated(true) == false)
        #expect(model.record?.isCurated == false)
        #expect(model.actionError == .tailscaleOff)
        #expect(log.changes.isEmpty)
    }

    @Test func deletingTakesTheMediaFirst() async {
        let log = ChangeLog()
        let (model, transport) = model(log: log, handler: { request in
            switch request.route {
            case "DELETE /media/record/5": .json([Fixture.media(51, recordID: 5)])
            case "DELETE /record/5": .json([Self.record])
            default: .notFound
            }
        })
        await model.load()
        #expect(await model.delete())
        #expect(await transport.routes.suffix(2) == ["DELETE /media/record/5", "DELETE /record/5"])
        #expect(model.isDeleted)
        #expect(log.changes == [.deleted(id: 5)])
    }

    @Test func aRecordShowingNoMediaStillHasItsMediaDeletedFirst() async {
        // Media added on the web after the detail loaded would otherwise be left on voyager's disk.
        let (model, transport) = model(detail: RecordDetail(record: Self.record), handler: { request in
            switch request.route {
            case "DELETE /media/record/5": .json([Media]())
            case "DELETE /record/5": .json([Self.record])
            default: .notFound
            }
        })
        await model.load()
        #expect(await model.delete())
        #expect(await transport.routes.suffix(2) == ["DELETE /media/record/5", "DELETE /record/5"])
    }

    @Test func curatingARecordDeletedElsewhereReportsItDeleted() async {
        let log = ChangeLog()
        let (model, _) = model(log: log, handler: { _ in
            .raw(#"{"error":{"code":"not_found","message":"x"},"message":"x"}"#, status: 404)
        })
        await model.load()
        #expect(await model.setCurated(true) == false)
        #expect(model.isDeleted)
        #expect(model.actionError == nil, "this screen closes; the library says it")
        #expect(log.changes == [.vanished(id: 5)])
    }

    @Test func aLoadThatWasOutDuringACurateDoesNotUndoIt() async {
        var stored = Self.record
        stored.isCurated = true
        stored.recordUpdatedAt = "2026-09-15 09:00:00"
        let curated = stored
        let stub = StubTransport { request in
            switch request.route {
            case "GET /record/5": .json(Self.detail) // as it was before the curate
            case "GET /record/5/links": .json(LinkGroupTests.bundle)
            case "PUT /record": .json(curated)
            default: .notFound
            }
        }
        let transport = HoldingTransport(stub)
        let model = RecordDetailModel(id: 5, environment: .test(transport))
        await model.load()
        await transport.hold { $0.route == "GET /record/5" }
        let refreshing = Task { await model.refresh() }
        await transport.waitUntilHeld()
        #expect(await model.setCurated(true))
        await transport.release()
        await refreshing.value
        #expect(model.record?.isCurated == true, "the switch stays where the server has it")
        #expect(model.state == .loaded)
        #expect(model.detail?.media.count == 1, "the rest of the load is taken")
    }

    @Test func aCurateFromTheListThatLandedDuringTheLoadIsShownOnceTheLoadIsDone() async {
        var stored = Self.record
        stored.isCurated = true
        stored.recordUpdatedAt = "2026-09-15 09:00:00"
        let curated = stored
        let landed = Mutex(false)
        let stub = StubTransport { request in
            switch request.route {
            case "GET /record/5": landed.withLock { $0 } ? .json(RecordDetail(record: curated)) : .json(Self.detail)
            case "GET /record/5/links": .json(LinkGroupTests.bundle)
            default: .notFound
            }
        }
        // The record is read before the list's curate lands, and its answer is slow.
        let transport = HoldingTransport(stub) { $0.route == "GET /record/5" }
        let model = RecordDetailModel(id: 5, environment: .test(transport))
        let loading = Task { await model.load() }
        await transport.waitUntilHeld()
        model.rowChanged(.init(isCurated: true, updatedAt: Self.record.recordUpdatedAt, working: true))
        landed.withLock { $0 = true }
        model.rowChanged(.init(isCurated: true, updatedAt: curated.recordUpdatedAt, working: false))
        await transport.release()
        await loading.value
        await model.settled()
        #expect(model.record?.isCurated == true, "checked again once the load it came during was done")
        #expect(await stub.routes.filter { $0 == "GET /record/5" }.count == 2)
    }

    @Test func aRowChangeDuringACurateHereIsComparedOnceItIsDone() async {
        var stored = Self.record
        stored.isCurated = true
        stored.recordUpdatedAt = "2026-09-15 09:00:00"
        let curated = stored
        var later = curated
        later.notes = "An agent's note"
        later.recordUpdatedAt = "2026-09-15 09:00:05"
        let edited = later
        let agentWrote = Mutex(false)
        let stub = StubTransport { request in
            switch request.route {
            case "GET /record/5": agentWrote.withLock { $0 } ? .json(RecordDetail(record: edited)) : .json(Self.detail)
            case "GET /record/5/links": .json(LinkGroupTests.bundle)
            case "PUT /record": .json(curated)
            default: .notFound
            }
        }
        let transport = HoldingTransport(stub)
        let model = RecordDetailModel(id: 5, environment: .test(transport))
        await model.load()
        await transport.hold { $0.route == "PUT /record" }
        let curating = Task { await model.setCurated(true) }
        await transport.waitUntilHeld()
        // A reloaded index brings the agent's edit, which the curate's answer predates.
        agentWrote.withLock { $0 = true }
        model.rowChanged(.init(isCurated: true, updatedAt: edited.recordUpdatedAt, working: false))
        #expect(await stub.routes.filter { $0 == "GET /record/5" }.count == 1, "not while curating")
        await transport.release()
        #expect(await curating.value)
        await model.settled()
        #expect(model.record?.notes == "An agent's note")
        #expect(await stub.routes.filter { $0 == "GET /record/5" }.count == 2)
    }

    @Test func aRowThatIsntAheadLeavesTheDetailAlone() async {
        var stored = Self.record
        stored.isCurated = true
        stored.recordUpdatedAt = "2026-09-15 09:00:00"
        let curated = stored
        let (model, transport) = model(handler: { _ in .json(curated) })
        await model.load()
        model.rowChanged(.init(isCurated: false, updatedAt: Self.record.recordUpdatedAt, working: false))
        model.rowChanged(.init(isCurated: true, updatedAt: "2026-09-01 00:00:00", working: false))
        model.rowChanged(.init(isCurated: true, updatedAt: "2026-10-01 00:00:00", working: true))
        model.rowChanged(nil)
        // Its own curate, coming back through the row.
        #expect(await model.setCurated(true))
        model.rowChanged(.init(isCurated: true, updatedAt: curated.recordUpdatedAt, working: false))
        await model.settled()
        #expect(await transport.routes.filter { $0 == "GET /record/5" }.count == 1, "never reloaded")
    }

    @Test func aRowIsAheadWhenItIsNewerOrSaysOtherwiseAtTheSameTime() {
        let record = Self.record
        let at = record.recordUpdatedAt
        func row(_ isCurated: Bool, _ updatedAt: DBTimestamp) -> RecordDetailModel.RowState {
            .init(isCurated: isCurated, updatedAt: updatedAt, working: false)
        }
        #expect(RecordDetailModel.rowIsAhead(row(false, "2026-09-14 15:00:01"), of: record))
        #expect(RecordDetailModel.rowIsAhead(row(true, at), of: record))
        #expect(!RecordDetailModel.rowIsAhead(row(false, at), of: record))
        #expect(!RecordDetailModel.rowIsAhead(row(true, "2026-09-14 14:59:59"), of: record))
    }

    @Test func aFailedMediaDeleteKeepsTheRecord() async {
        let (model, transport) = model(handler: { _ in .raw(#"{"message":"EACCES"}"#, status: 500) })
        await model.load()
        #expect(await model.delete() == false)
        #expect(!model.isDeleted)
        #expect(model.actionError == .server(status: 500, message: "EACCES"))
        #expect(await transport.routes.last == "DELETE /media/record/5", "the record wasn't deleted after")
    }

    @Test func itsEditorOutlivesIt() async throws {
        // A reload moved the selection while the editor was open: the detail is gone, the editor and its text aren't.
        let log = ChangeLog()
        var stored = Self.record
        stored.title = "Tiny internets, again"
        let renamed = stored
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/5": .json(Self.detail)
            case "GET /record/5/links": .json(LinkGroupTests.bundle)
            default: .json(renamed)
            }
        }
        var detail: RecordDetailModel? = RecordDetailModel(id: 5, environment: .test(transport), onChange: log.handler)
        await detail?.load()
        let editor = try #require(detail?.makeEditor())
        weak let gone = detail
        detail = nil
        #expect(gone == nil)

        editor.draft.title = "Tiny internets, again"
        #expect(await editor.save() == renamed)
        #expect(log.changes == [.updated(renamed)], "straight to the library")
    }

    @Test func itsEditorUpdatesItAndPassesTheChangeOn() async throws {
        let log = ChangeLog()
        var stored = Self.record
        stored.title = "Tiny internets, again"
        let renamed = stored
        let (model, transport) = model(log: log, handler: { _ in .json(renamed) })
        #expect(model.makeEditor() == nil, "nothing to edit before the record loads")
        await model.load()

        let editor = try #require(model.makeEditor())
        editor.draft.title = "Tiny internets, again"
        #expect(await editor.save() == renamed)
        #expect(model.record?.title == "Tiny internets, again")
        #expect(log.changes == [.updated(renamed)])
        let body = try #require(await transport.requests.last).json()
        #expect(body["id"] as? Int == 5)
        #expect(body["slug"] as? String == "tiny-internets")
    }
}
