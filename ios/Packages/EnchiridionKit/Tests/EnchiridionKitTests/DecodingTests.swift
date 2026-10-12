@testable import EnchiridionKit
import Foundation
import Testing

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

@Suite struct DecodingTests {
    @Test func listRow() throws {
        let row = try decode(ListRecord.self, Fixture.listRow)
        #expect(row.id == 812)
        #expect(row.slug == "tiny-internets")
        #expect(row.title == "Tiny internets")
        #expect(row.type == .artifact)
        #expect(row.source == .manual)
        #expect(row.content == nil)
        #expect(row.summary == "Page meta description")
        #expect(row.isCurated == false)
        #expect(row.recordCreatedAt.raw == "2026-10-11 22:27:12")
        #expect(row.contentCreatedAt == nil)
        #expect(row.media.isEmpty)
        #expect(row.score == nil)
        #expect(row.outgoingLinks.count == 3)
        #expect(row.outgoingLinks[0] == .init(predicate: .hasFormat, target: RecordRef(id: 4, title: "Article", slug: "article")))
        #expect(row.incomingLinks.map(\.predicate) == [.relatedTo, .containedBy, .containedBy, .quotes])
    }

    @Test func listRowDerivedValues() throws {
        let row = try decode(ListRecord.self, Fixture.listRow)
        #expect(row.domain == "example.com")
        #expect(row.creator == RecordRef(id: 120, title: "Jane Doe", slug: "jane-doe"))
        #expect(row.parent == nil)
        #expect(row.childCount == 3)   // two contained_by and a quotes; related_to isn't containment
        #expect(row.targets(.taggedWith).map(\.slug) == ["web"])
        #expect(row.targets(ofType: .description).map(\.slug) == ["article", "web"])

        let highlight = try decode(ListRecord.self, Fixture.highlightRow)
        #expect(highlight.parent?.slug == "a-book")
        #expect(highlight.childCount == 0)
        #expect(highlight.domain == nil)
        #expect(highlight.title == nil)
        #expect(highlight.source == .readwise)
        #expect(highlight.contentCreatedAt?.raw == "2024-12-31 23:59:59")
        #expect(highlight.media.first?.isImage == true)
        #expect(highlight.media.first?.width == 1200)
    }

    @Test func searchRowWithUnknownValues() throws {
        let row = try decode(ListRecord.self, Fixture.searchRow)
        #expect(row.score == 0.032266458495966696)
        #expect(row.type.rawValue == "hypothesis")
        #expect(!row.type.isKnown)
        #expect(row.type.displayName == "Hypothesis")
        #expect(row.source == nil)
        #expect(row.domain == nil)
        let predicate = try #require(row.outgoingLinks.first?.predicate)
        #expect(predicate.rawValue == "inspired_by")
        #expect(predicate.name == "inspired by")
        #expect(predicate.type == nil)
        #expect(row.targets(ofType: .description).isEmpty)
        #expect(row.childCount == 0)
    }

    @Test func listRowRoundTrips() throws {
        let row = try decode(ListRecord.self, Fixture.highlightRow)
        let again = try JSONDecoder().decode(ListRecord.self, from: JSONEncoder().encode(row))
        #expect(again == row)
    }

    @Test func detail() throws {
        let detail = try decode(RecordDetail.self, Fixture.detail)
        #expect(detail.id == 812)
        #expect(detail.title == "Tiny internets")          // through dynamic member lookup
        #expect(detail.record.recordUpdatedAt.raw == "2026-10-11 22:30:01")
        #expect(detail.contentUpdatedAt == nil)
        #expect(detail.outgoingLinks.count == 2)
        let format = try #require(detail.outgoingLinks.first)
        #expect(format.predicate == .hasFormat)
        #expect(format.target.type == .concept)
        #expect(format.target.isCurated)
        #expect(detail.creator?.title == "Jane Doe")
        #expect(detail.creator?.source == nil)
        #expect(detail.targets(.hasFormat).map(\.slug) == ["article"])

        let media = try #require(detail.media.first)
        #expect(media.url == "/uploads/images/3f1ce9.jpg")
        #expect(media.contentTypeString == "image/jpeg")
        #expect(media.fileSize == 183_422)
        #expect(media.url(relativeTo: URL(string: "https://enchiridion-api.chsmc.tools")!)?.absoluteString
            == "https://enchiridion-api.chsmc.tools/uploads/images/3f1ce9.jpg")

        let archive = try #require(detail.archives.first)
        #expect(archive.status == .ok)
        #expect(archive.path == "example.com/2026-10-11")
        #expect(archive.error == nil)
        #expect(archive.archivedAt.raw == "2026-10-11 22:31:00")
    }

    @Test func detailRoundTrips() throws {
        let detail = try decode(RecordDetail.self, Fixture.detail)
        let again = try JSONDecoder().decode(RecordDetail.self, from: JSONEncoder().encode(detail))
        #expect(again == detail)
    }

    @Test func record() throws {
        let record = try decode(Record.self, Fixture.record)
        #expect(record.id == 812)
        #expect(record.isCurated)
        #expect(record.content == "Body")
        #expect(record.notes == "A note")
        #expect(record.contentCreatedAt?.raw == "2026-03-14 16:12:00")
        #expect(record.contentUpdatedAt == nil)
        #expect(record.domain == "example.com")
    }

    @Test func bySlugDecodesAsRecord() throws {
        let record = try decode(Record.self, Fixture.bySlug)
        #expect(record.slug == "tiny-internets")
        #expect(record.summary == nil)
    }

    @Test func deletedRows() throws {
        let rows = try decode([Record].self, "[\(Fixture.record)]")
        #expect(rows.map(\.id) == [812])
        #expect(try decode([Record].self, "[]").isEmpty)
    }

    @Test func link() throws {
        let link = try decode(Link.self, Fixture.link)
        #expect(link.id == 1400)
        #expect(link.sourceId == 812)
        #expect(link.targetId == 4)
        #expect(link.predicate == .hasFormat)
        #expect(link.notes == nil)
    }

    @Test func linksBundle() throws {
        let bundle = try decode(LinksBundle.self, Fixture.linksBundle)
        #expect(bundle.id == 812)
        let outgoing = try #require(bundle.outgoingLinks.first)
        #expect(outgoing.id == 1400)
        #expect(outgoing.targetId == 4)                  // the nested target has no id
        #expect(outgoing.predicate == .hasFormat)
        #expect(outgoing.target == .init(title: "Article", slug: "article"))
        let incoming = try #require(bundle.incomingLinks.first)
        #expect(incoming.sourceId == 901)
        #expect(incoming.notes == "from the book")
        #expect(incoming.source.title == nil)
        #expect(incoming.source.content == "A highlighted passage.")
        #expect(incoming.predicate.displayName(.incoming) == "contains")

        let again = try JSONDecoder().decode(LinksBundle.self, from: JSONEncoder().encode(bundle))
        #expect(again == bundle)
    }

    @Test func identity() throws {
        #expect(try decode(Info.self, Fixture.infoOn) == Info(name: "enchiridion", auth: ["tailscale"]))
        #expect(try decode(Info.self, Fixture.infoOff).auth.isEmpty)
        let me = try decode(Me.self, Fixture.meTailscale)
        #expect(me == Me(scheme: "tailscale", device: Device(id: "nXYZ123CNTRL", name: "vern"), user: "chase@github"))
        let local = try decode(Me.self, Fixture.meLocal)
        #expect(local.scheme == "local")
        #expect(local.device == nil)
        #expect(local.user == nil)
        #expect(try decode(Me.self, #"{"scheme":"open"}"#) == Me(scheme: "open"))
    }

    @Test func archiveStatusIsOpen() throws {
        let json = Fixture.detail.replacingOccurrences(of: #""status":"ok""#, with: #""status":"queued""#)
        let detail = try decode(RecordDetail.self, json)
        #expect(detail.archives.first?.status.rawValue == "queued")
        #expect(detail.archives.first?.status.isKnown == false)
    }

    @Test func missingRequiredFieldFails() {
        let json = Fixture.record.replacingOccurrences(of: #""slug":"tiny-internets","#, with: "")
        #expect(throws: DecodingError.self) { try decode(Record.self, json) }
    }

    @Test(arguments: [
        ("https://www.example.com/a", "example.com"),
        ("https://EXAMPLE.com", "example.com"),
        ("http://sub.www.example.com/x", "sub.www.example.com"),
        ("https://www.chsmc.org/", "chsmc.org"),
        ("  https://x.com/status/1  ", "x.com"),
        ("not a url", nil),
        ("", nil),
    ] as [(String, String?)])
    func domain(url: String, expected: String?) {
        #expect(displayDomain(url) == expected)
    }

    @Test func mergeKeepsRelations() throws {
        var row = try decode(ListRecord.self, Fixture.listRow)
        let saved = try decode(Record.self, Fixture.record)
        row.merge(saved)
        #expect(row.isCurated)
        #expect(row.content == "Body")
        #expect(row.recordUpdatedAt.raw == "2026-10-11 22:30:01")
        #expect(row.outgoingLinks.count == 3)            // kept: a save doesn't return them

        let fresh = ListRecord(saved)
        #expect(fresh.id == saved.id)
        #expect(fresh.notes == "A note")
        #expect(fresh.media.isEmpty)
        #expect(fresh.outgoingLinks.isEmpty)
    }
}
