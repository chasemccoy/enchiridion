#if DEBUG
import EnchiridionKit
import Foundation
import SwiftUI

/// Static records for previews, built from Kit's own types. Nothing here touches the network: media URLs are
/// relative, so images show their placeholder.
public enum PreviewSamples {
    /// A made-up Tailscale node, never a real one.
    public static let device = Device(id: "n7f3a9c2e1bCNTRL", name: "vern")

    public static let markdown = """
        # Notes on *Ancillary Justice*
        The narrator was a ship.
        Now it is one body, and it keeps count of what it lost.

        - Gender is ==unmarked== in Radch speech
        - Tea matters more than it should
          and so do gloves
        1. One
        2. Two

        > "Because I wanted to."
        > The whole book turns on that line.

        See https://annleckie.com and [the Hugo list](https://www.thehugoawards.org), or `radch --help`.

        ```
        let ship = "Justice of Toren"
        ```
        ---
        In 1984. A year.
        """

    private static let book = RecordRef(id: 412, title: "Ancillary Justice", slug: "ancillary-justice")
    private static let leckie = RecordRef(id: 98, title: "Ann Leckie", slug: "ann-leckie")
    private static let novel = RecordRef(id: 7, title: "Novel", slug: "novel")
    private static let scienceFiction = RecordRef(id: 31, title: "Science fiction", slug: "science-fiction")

    /// An article, a book with a cover and highlights, one of its highlights, a concept, an entity and a tweet.
    public static let listRecords: [ListRecord] = [
        ListRecord(
            id: 777, slug: "the-case-for-slow-software", title: "The case for slow software",
            url: "https://www.example.com/essays/slow-software",
            summary: "Software that waits for you is kinder than software that hurries you. An essay on latency, "
                + "attention and the small delays that make tools feel considered.",
            recordCreatedAt: "2026-10-09 14:12:00", notes: "Pairs well with the Ink & Switch local-first essay.",
            outgoingLinks: [
                .init(predicate: .createdBy, target: RecordRef(id: 120, title: "Robin Sloan", slug: "robin-sloan")),
                .init(predicate: .taggedWith,
                      target: RecordRef(id: 33, title: "Software design", slug: "software-design")),
            ]
        ),
        ListRecord(
            id: 412, slug: "ancillary-justice", title: "Ancillary Justice",
            url: "https://annleckie.com/novel/ancillary-justice/",
            summary: "A warship's AI, reduced to a single human body, sets out for revenge.",
            recordCreatedAt: "2026-10-07 09:30:00", isCurated: true, source: .readwise,
            media: [
                Media(id: 9, recordId: 412, url: "/uploads/images/ancillary-justice.jpg", altText: "The cover",
                      type: "image", contentTypeString: "image/jpeg", width: 600, height: 900,
                      recordCreatedAt: "2026-10-07 09:30:00"),
            ],
            outgoingLinks: [
                .init(predicate: .createdBy, target: leckie),
                .init(predicate: .hasFormat, target: novel),
                .init(predicate: .taggedWith, target: scienceFiction),
            ],
            incomingLinks: [.init(predicate: .containedBy), .init(predicate: .containedBy), .init(predicate: .quotes)]
        ),
        ListRecord(
            id: 413, slug: "note-e5f4405b",
            content: "I had been a ship.\nNow I was a single body, with ==two arms== and a bad temper.",
            recordCreatedAt: "2026-10-07 09:31:00", source: .readwise,
            outgoingLinks: [.init(predicate: .containedBy, target: book)]
        ),
        ListRecord(
            id: 300, slug: "attention-as-a-moral-act", title: "Attention as a moral act", type: .concept,
            summary: "Simone Weil: attention, taken to its highest degree, is the same thing as prayer.",
            recordCreatedAt: "2026-10-02 18:05:00"
        ),
        ListRecord(
            id: 98, slug: "ann-leckie", title: "Ann Leckie", url: "https://annleckie.com", type: .entity,
            recordCreatedAt: "2026-09-28 11:00:00", isCurated: true
        ),
        ListRecord(
            id: 501, slug: "note-1a2b3c4d", url: "https://twitter.com/example/status/1",
            content: "Every tool is a theory of its user.", recordCreatedAt: "2026-09-14 08:45:00", source: .twitter
        ),
    ]

    /// The article above as a full record.
    public static let record = Record(
        id: 777, slug: "the-case-for-slow-software", title: "The case for slow software",
        url: "https://www.example.com/essays/slow-software",
        summary: "Software that waits for you is kinder than software that hurries you.",
        content: markdown, notes: "Pairs well with the Ink & Switch local-first essay.", source: .manual,
        recordCreatedAt: "2026-10-09 14:12:00", contentCreatedAt: "2026-03-14 00:00:00"
    )

    /// The record with its creator and a tag linked, as `GET /record/:id` returns it.
    public static let detail = RecordDetail(
        record: record,
        outgoingLinks: [
            .init(predicate: .createdBy, target: Record(id: 120, slug: "robin-sloan", type: .entity,
                                                        title: "Robin Sloan", recordCreatedAt: "2026-01-02 10:00:00")),
            .init(predicate: .taggedWith, target: Record(id: 33, slug: "software-design", type: .concept,
                                                         title: "Software design",
                                                         recordCreatedAt: "2026-01-02 10:00:00")),
        ]
    )
}

extension View {
    /// `enchiridionRoot()` for previews, with Martina Plantijn registered from the web app's copy in this checkout
    /// (a package preview has no app bundle to read it from).
    func previewRoot() -> some View {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent() // Components
            .deletingLastPathComponent() // EnchiridionUI (sources)
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // EnchiridionUI (package)
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent()
        FontRegistry.register(directory: repository.appending(path: "app/public/fonts/martina-plantijn"))
        return enchiridionRoot()
    }
}
#endif
