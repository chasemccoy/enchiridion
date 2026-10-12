import EnchiridionKit
import Foundation
import Testing

/// Decodes real responses from a running API, read-only: `POST /records` (a read) and GETs, never a write.
///
///     ENCHIRIDION_LIVE=1 swift test --filter LiveSmokeTests
///
/// `ENCHIRIDION_LIVE_SERVER` overrides the origin (default `http://localhost:4321`).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ENCHIRIDION_LIVE"] == "1", "set ENCHIRIDION_LIVE=1"),
       .serialized)
struct LiveSmokeTests {
    private let client: EnchiridionClient = {
        let origin = ProcessInfo.processInfo.environment["ENCHIRIDION_LIVE_SERVER"] ?? "http://localhost:4321"
        return EnchiridionClient(.init(server: URL(string: origin)!, role: .app, appVersion: "0.1-test"))
    }()

    @Test func firstPageAndItsFirstRecord() async throws {
        let rows = try await client.list(ListQuery(limit: 20))
        #expect(rows.count == 20)
        #expect(rows.allSatisfy { $0.recordCreatedAt.date != nil })
        let first = try #require(rows.first)

        let detail = try await client.record(id: first.id)
        #expect(detail.id == first.id)
        #expect(detail.slug == first.slug)
        #expect(detail.title == first.title)

        let bySlug = try await client.record(slug: first.slug)
        #expect(bySlug?.id == first.id)
        #expect(try await client.record(slug: "no-such-slug-\(Slug.fallback())") == nil)

        let links = try await client.links(id: first.id)
        #expect(links.id == first.id)
    }

    @Test func wholeIndexDecodes() async throws {
        let rows = try await client.list(.index)
        #expect(rows.count > 100)
        #expect(Set(rows.map(\.id)).count == rows.count)
        // Every timestamp the list carries parses, and the order is the requested one.
        #expect(rows.allSatisfy { $0.recordCreatedAt.date != nil && $0.recordUpdatedAt.date != nil })
        #expect(rows.allSatisfy { $0.contentCreatedAt.map { $0.date != nil } ?? true })
        #expect(zip(rows, rows.dropFirst()).allSatisfy { $0.recordCreatedAt >= $1.recordCreatedAt })
        #expect(rows.allSatisfy { $0.type.isKnown })
        #expect(rows.allSatisfy { row in row.outgoingLinks.allSatisfy(\.predicate.isKnown) })

        // A record with media and one with outgoing links decode in full, with their links.
        if let withMedia = rows.first(where: { !$0.media.isEmpty }) {
            let detail = try await client.record(id: withMedia.id)
            #expect(detail.media.map(\.id) == withMedia.media.map(\.id))
        }
        if let linked = rows.first(where: { $0.outgoingLinks.count > 1 }) {
            let detail = try await client.record(id: linked.id)
            #expect(detail.outgoingLinks.count >= linked.outgoingLinks.count)
            let bundle = try await client.links(id: linked.id)
            #expect(bundle.outgoingLinks.count >= linked.outgoingLinks.count)
        }
    }

    @Test func missingRecordIsNotFound() async {
        await #expect(throws: EnchiridionError.notFound) {
            try await client.record(id: 99_999_999)
        }
    }
}
