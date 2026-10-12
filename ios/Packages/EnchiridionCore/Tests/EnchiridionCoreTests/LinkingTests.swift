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
