import EnchiridionKit
import struct EnchiridionKit.Predicate
import Foundation
import Synchronization
import Testing
@testable import EnchiridionCore

struct PendingLinkTests {
    @Test func linkingTheSameRecordAgainChangesHowNotHowMany() {
        var draft = ShareDraft(title: "Tiny internets")
        let author = Fixture.row(7, title: "Robin Sloan", type: .entity)
        draft.link(PendingLink(author, predicate: .createdBy))
        draft.link(PendingLink(Fixture.row(4, title: "Article", type: .concept), predicate: .hasFormat))
        draft.link(PendingLink(author, predicate: .about))
        #expect(draft.links.map(\.targetID) == [7, 4])
        #expect(draft.links.first?.predicate == .about)
    }

    @Test func theOptionsAreTheCanonicalPredicates() {
        #expect(Predicate.linkOptions.first == .createdBy)
        #expect(Predicate.linkOptions.contains(.taggedWith))
        #expect(!Predicate.linkOptions.contains(.creatorOf))
        #expect(Predicate.createdBy.menuName == "Created by")
    }

    @Test func typeAndCurationReachTheCreate() {
        let draft = ShareDraft(title: "Robin Sloan", type: .entity, isCurated: true)
        let input = draft.input(slug: "robin-sloan")
        #expect(input.type == .entity)
        #expect(input.isCurated)
    }
}

@MainActor
struct ShareLinkTests {
    private nonisolated static let input = ShareInput(url: URL(string: "https://example.com/tiny")!,
                                                     title: "Tiny internets")
    private nonisolated static let saved = Fixture.record(42, slug: "tiny-internets", title: "Tiny internets",
                                                         url: "https://example.com/tiny")

    private func server(failLinkTo failing: Int? = nil) -> StubTransport {
        let failingOnce = Mutex(failing)
        return StubTransport { request in
            switch request.route {
            case "GET /record/slug/tiny-internets":
                return .notFound
            case "PUT /record":
                return .json(Self.saved)
            case "PUT /link":
                let body = request.json()
                let target = body["targetId"] as? Int
                if let target, failingOnce.withLock({ $0 == target }) {
                    failingOnce.withLock { $0 = nil }
                    return .raw(#"{"message":"boom"}"#, status: 500)
                }
                return .raw(#"{"id":1,"sourceId":42,"targetId":\#(target ?? 0),"predicate":"\#(body["predicate"] as? String ?? "")","notes":null,"recordCreatedAt":"2026-10-12 10:00:00","recordUpdatedAt":"2026-10-12 10:00:00"}"#)
            default:
                return .notFound
            }
        }
    }

    @Test func linksAreAddedOnceTheRecordIsSaved() async throws {
        let transport = server()
        let model = ShareComposeModel(input: Self.input, environment: .test(transport))
        model.draft.link(PendingLink(Fixture.row(7, title: "Robin Sloan", type: .entity), predicate: .createdBy))
        model.draft.link(PendingLink(Fixture.row(4, title: "Article", type: .concept), predicate: .hasFormat))
        await model.save()
        #expect(model.state == .saved(Self.saved))
        #expect(model.failedLinks.isEmpty)
        let links = await transport.requests.filter { $0.route == "PUT /link" }.map { $0.json() }
        #expect(links.count == 2)
        #expect(links[0]["sourceId"] as? Int == 42)
        #expect(links[0]["targetId"] as? Int == 7)
        #expect(links[0]["predicate"] as? String == "created_by")
        #expect(links[1]["targetId"] as? Int == 4)
        #expect(links[1]["predicate"] as? String == "has_format")
    }

    @Test func aLinkThatFailsIsKeptForRetry() async throws {
        let transport = server(failLinkTo: 4)
        let model = ShareComposeModel(input: Self.input, environment: .test(transport))
        model.draft.link(PendingLink(Fixture.row(7, title: "Robin Sloan", type: .entity), predicate: .createdBy))
        model.draft.link(PendingLink(Fixture.row(4, title: "Article", type: .concept), predicate: .hasFormat))
        await model.save()
        #expect(model.state == .saved(Self.saved), "the record saved; only a link didn't")
        #expect(model.failedLinks.map(\.targetID) == [4])
        #expect(model.canRetryLinks)
        await model.retryLinks()
        #expect(model.failedLinks.isEmpty)
        #expect(!model.canRetryLinks)
        let creates = await transport.requests.filter { $0.route == "PUT /record" }
        #expect(creates.count == 1, "retrying links never creates the record again")
    }
}

@MainActor
struct RecordSearchModelTests {
    @Test func searchesWhatIsTypedLeavingOutExcludedRecords() async {
        let transport = StubTransport { request in
            request.route.hasPrefix("GET /search/hybrid")
                ? .json([Fixture.row(1, title: "Robin Sloan"), Fixture.row(2, title: "Robin Hood")])
                : .notFound
        }
        let search = RecordSearchModel(environment: .test(transport))
        search.excludedIDs = [2]
        search.query = "robin"
        await search.settle()
        #expect(search.results.map(\.id) == [1])
        #expect(!search.isSearching)
        search.query = "  "
        #expect(search.results.isEmpty)
    }
}

@MainActor
struct ShareTitleTests {
    private let page = URL(string: "https://example.com/tiny")!

    @Test func theItemsOwnTitleFillsInForAMissingOne() {
        #expect(ShareInput.from(javaScript: nil, url: page, text: nil, itemTitle: " Tiny internets ")
            == ShareInput(url: page, title: "Tiny internets"))
        #expect(ShareInput.from(javaScript: nil, url: page, text: "From the page", itemTitle: "From the item")?.title
            == "From the page")
        #expect(ShareInput.from(javaScript: nil, url: page, text: nil, itemTitle: page.absoluteString)?.title == nil,
                "a title that is only the link isn't one")
        #expect(ShareInput.from(javaScript: nil, url: nil, text: "A thought", itemTitle: "Notes")
            == ShareInput(text: "A thought"))
    }

    @Test func aFetchedTitleFillsABlankTitleOnce() {
        let model = ShareComposeModel(input: ShareInput(url: page), environment: .test(StubTransport { _ in .notFound }))
        model.suggestTitle("  Tiny\ninternets ")
        #expect(model.draft.title == "Tiny internets")
        model.draft.title = ""
        model.suggestTitle("Again")
        #expect(model.draft.title == "", "a title cleared on purpose stays cleared")
    }

    @Test func aFetchedTitleNeverReplacesOneTyped() {
        let model = ShareComposeModel(input: ShareInput(url: page), environment: .test(StubTransport { _ in .notFound }))
        model.draft.title = "Mine"
        model.suggestTitle("The page's")
        #expect(model.draft.title == "Mine")
    }
}

@MainActor
struct DetailLinkingTests {
    private nonisolated static let detail = RecordDetail(record: Fixture.record(5, slug: "tiny", title: "Tiny"))

    /// Record 5, linked to 7; the server suggests 7 (linked meanwhile), 8 and 9.
    private func server(failPut: Bool = false) -> StubTransport {
        let linked = Mutex([7])
        return StubTransport { request in
            switch request.route {
            case "GET /record/5":
                return .json(Self.detail)
            case "GET /record/5/links":
                let targets = linked.withLock { $0 }
                return .json(LinksBundle(id: 5, outgoingLinks: targets.map {
                    .init(link: Fixture.link($0 * 10, from: 5, to: $0, .relatedTo), target: .init(title: "R\($0)", slug: "r\($0)"))
                }))
            case "GET /record/5/similar":
                return .json([7, 8, 9].map { SimilarRecord(record: Fixture.record($0, title: "R\($0)"), score: 0.5) })
            case "PUT /link":
                if failPut { return .raw(#"{"message":"boom"}"#, status: 500) }
                let target = request.json()["targetId"] as? Int ?? 0
                linked.withLock { $0.append(target) }
                return .json(Fixture.link(target * 10, from: 5, to: target, .relatedTo))
            case "DELETE /link/70":
                linked.withLock { $0.removeAll { $0 == 7 } }
                return .json([Fixture.link(70, from: 5, to: 7, .relatedTo)])
            default:
                return .notFound
            }
        }
    }

    @Test func suggestionsLeaveOutLinkedRecords() async {
        let model = RecordDetailModel(id: 5, environment: .test(server()))
        await model.load()
        await model.settled()
        #expect(model.similar.map(\.id) == [8, 9])
    }

    @Test func linkingASuggestionMovesItToTheLinks() async {
        let model = RecordDetailModel(id: 5, environment: .test(server()))
        await model.load()
        await model.settled()
        #expect(await model.addLink(to: 8, predicate: .about))
        #expect(model.similar.map(\.id) == [9])
        #expect(model.linkGroups.flatMap(\.links).map(\.recordID) == [7, 8])
        #expect(model.makeLinkSearch().excludedIDs == [5, 7, 8])
    }

    @Test func removingALink() async {
        let model = RecordDetailModel(id: 5, environment: .test(server()))
        await model.load()
        let linked = try! #require(model.linkGroups.first?.links.first)
        #expect(await model.removeLink(linked))
        #expect(model.linkGroups.isEmpty)
    }

    @Test func aFailedLinkSaysSo() async {
        let model = RecordDetailModel(id: 5, environment: .test(server(failPut: true)))
        await model.load()
        #expect(await model.addLink(to: 8, predicate: .about) == false)
        #expect(model.actionError != nil)
        #expect(!model.isLinking)
    }
}

@MainActor
struct EditorLinkingTests {
    @Test func aNewRecordsLinksFollowItsCreate() async {
        let saved = Fixture.record(42, slug: "tiny", title: "Tiny")
        let failing = Mutex(true)
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/slug/tiny": return .notFound
            case "PUT /record": return .json(saved)
            case "PUT /link":
                let target = request.json()["targetId"] as? Int ?? 0
                if target == 4, failing.withLock({ $0 }) {
                    failing.withLock { $0 = false }
                    return .raw(#"{"message":"boom"}"#, status: 500)
                }
                return .json(Fixture.link(1, from: 42, to: target, .createdBy))
            default: return .notFound
            }
        }
        let model = RecordEditorModel(environment: .test(transport))
        model.draft.title = "Tiny"
        #expect(!model.hasChanges || model.draft.title == "Tiny")
        model.links.link(PendingLink(Fixture.row(7, title: "Ada", type: .entity), predicate: .createdBy))
        model.links.link(PendingLink(Fixture.row(4, title: "Essay"), predicate: .hasFormat))
        #expect(await model.save() == saved)
        #expect(model.failedLinks.map(\.targetID) == [4])
        await model.retryLinks()
        #expect(model.failedLinks.isEmpty)
        let creates = await transport.routes.filter { $0 == "PUT /record" }
        #expect(creates.count == 1, "a links retry never creates again")
    }

    @Test func pendingLinksCountAsChanges() {
        let model = RecordEditorModel(environment: .test(StubTransport { _ in .notFound }))
        #expect(!model.hasChanges)
        model.links.link(PendingLink(Fixture.row(7, title: "Ada"), predicate: .createdBy))
        #expect(model.hasChanges)
    }
}

struct RecordShortcutsTests {
    @Test func randomPicksFromCuratedRecords() async throws {
        let transport = StubTransport { request in
            #expect(request.json()["filters"].flatMap { ($0 as? [String: Any])?["isCurated"] as? Bool } == true)
            return .json([Fixture.row(1, title: "One", curated: true), Fixture.row(2, title: "Two", curated: true)])
        }
        let shortcuts = RecordShortcuts(environment: .test(transport))
        #expect(try await shortcuts.random(using: { $0.last })?.id == 2)
    }

    @Test func aSampleIsDistinctAndCapped() async throws {
        let transport = StubTransport { _ in .json((1 ... 5).map { Fixture.row($0, title: "R\($0)", curated: true) }) }
        let shortcuts = RecordShortcuts(environment: .test(transport), role: .widget)
        #expect(try await shortcuts.sample(3, using: { $0.reversed() }).map(\.id) == [5, 4, 3])
        #expect(try await shortcuts.sample(9).count == 5)
        #expect(await transport.requests.first?.headers["X-Enchiridion-Client"]?.hasSuffix(" widget") == true)
        _ = try await shortcuts.sample(1, type: .artifact)
        let filters = await transport.requests.last?.json()["filters"] as? [String: Any]
        #expect(filters?["type"] as? String == "artifact")
    }

    @Test func imagesComeEveryOtherPickWhileTheyLast() {
        func row(_ id: Int, image: Bool) -> ListRecord {
            var row = Fixture.row(id, title: "R\(id)", curated: true)
            if image { row.media = [Fixture.media(id * 10, recordID: id)] }
            return row
        }
        let rows = [row(1, image: false), row(2, image: false), row(3, image: true), row(4, image: false),
                    row(5, image: true)]
        #expect(RecordShortcuts.alternatingImages(rows, count: 5).map(\.id) == [3, 1, 5, 2, 4])
        #expect(RecordShortcuts.alternatingImages(rows, count: 2).map(\.id) == [3, 1])
        #expect(RecordShortcuts.alternatingImages(Array(rows.prefix(2)), count: 4).map(\.id) == [1, 2])
    }

    @Test func aSampleRetriesWhileTheNetworkIsDown() async throws {
        let calls = Mutex(0)
        let transport = StubTransport { _ in
            let call = calls.withLock { $0 += 1; return $0 }
            if call < 3 { throw URLError(.timedOut) }
            return .json([Fixture.row(1, title: "One", curated: true)])
        }
        let shortcuts = RecordShortcuts(environment: .test(transport), role: .widget)
        #expect(try await shortcuts.sampleRetrying(5, pause: .zero).map(\.id) == [1])
        #expect(calls.withLock { $0 } == 3)
    }

    @Test func aSampleGivesUpAfterItsAttemptsAndOnLastingErrors() async {
        let calls = Mutex(0)
        let down = StubTransport { _ in calls.withLock { $0 += 1 }; throw URLError(.cannotConnectToHost) }
        await #expect(throws: EnchiridionError.unreachable) {
            try await RecordShortcuts(environment: .test(down)).sampleRetrying(5, attempts: 2, pause: .zero)
        }
        #expect(calls.withLock { $0 } == 2)
        let refused = StubTransport { _ in .raw(#"{"message":"no","device":null}"#, status: 401) }
        await #expect(throws: EnchiridionError.unauthorized(device: nil)) {
            try await RecordShortcuts(environment: .test(refused)).sampleRetrying(5)
        }
    }

    @Test @MainActor func savingALinkMakesAnArtifact() async throws {
        let saved = Fixture.record(42, slug: "tiny-internets", title: "Tiny internets", url: "https://example.com/tiny")
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/slug/tiny-internets": return .notFound
            case "PUT /record":
                let body = request.json()
                #expect(body["type"] as? String == "artifact")
                #expect(body["notes"] as? String == "Read later")
                #expect(body["url"] as? String == "https://example.com/tiny")
                return .json(saved)
            default: return .notFound
            }
        }
        let record = try await RecordShortcuts(environment: .test(transport))
            .save(url: URL(string: "https://example.com/tiny")!, title: " Tiny internets ", note: "Read later")
        #expect(record == saved)
    }
}

struct DeepLinkTests {
    @Test func recordLinksRoundTrip() {
        #expect(DeepLink.record(812).absoluteString == "enchiridion://record/812")
        #expect(DeepLink.recordID(from: DeepLink.record(812)) == 812)
        #expect(DeepLink.recordID(from: URL(string: "ENCHIRIDION://Record/7")!) == 7)
    }

    @Test func anythingElseIsNotARecord() {
        for link in ["enchiridion://record/", "enchiridion://record/abc", "enchiridion://record/0",
                     "enchiridion://record/1/2", "enchiridion://search/1", "https://example.com/record/1"] {
            #expect(DeepLink.recordID(from: URL(string: link)!) == nil, "\(link)")
        }
    }
}

@MainActor
struct RememberedFiltersTests {
    /// Preferences kept in memory, as UserDefaults would across launches.
    private static func memory() -> Preferences {
        let store = Mutex<[String: Data]>([:])
        return Preferences(load: { key in store.withLock { $0[key] } },
                           save: { key, data in store.withLock { $0[key] = data } })
    }

    private func environment(_ preferences: Preferences) -> AppEnvironment {
        var environment = AppEnvironment.test(StubTransport { _ in .notFound })
        environment.preferences = preferences
        return environment
    }

    @Test func filtersAndSortSurviveARelaunch() {
        let preferences = Self.memory()
        let first = LibraryModel(environment: environment(preferences))
        #expect(first.filters == LibraryModel.Filters())
        first.filters.type = .concept
        first.filters.needsCuration = true
        first.filters.hasMedia = true
        first.filters.sort = .title
        let relaunched = LibraryModel(environment: environment(preferences))
        #expect(relaunched.filters == LibraryModel.Filters(type: .concept, needsCuration: true, hasMedia: true,
                                                           sort: .title))
    }

    @Test func unreadableFiltersFallBackToDefaults() {
        let preferences = Self.memory()
        preferences.save(LibraryModel.filtersKey, Data("{\"type\":".utf8))
        #expect(LibraryModel(environment: environment(preferences)).filters == LibraryModel.Filters())
    }
}
