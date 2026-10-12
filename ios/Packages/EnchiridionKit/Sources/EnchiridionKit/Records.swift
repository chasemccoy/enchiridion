import Foundation

// Response shapes from `backend/db/queries/records.ts` and the schema in `backend/db/schema/*`. Every key is the
// server's camelCase, so Codable is synthesized wherever the shape is flat.

/// A full `records` row (the server's RecordSelect): what `PUT /record` and `DELETE /record/:id` return, and each
/// outgoing link's target in `GET /record/:id`.
public struct Record: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var slug: String
    public var type: RecordType
    public var title: String?
    public var url: String?
    public var isCurated: Bool
    public var summary: String?
    public var content: String?
    public var notes: String?
    public var source: RecordSource?
    public var recordCreatedAt: DBTimestamp
    public var recordUpdatedAt: DBTimestamp
    public var contentCreatedAt: DBTimestamp?
    public var contentUpdatedAt: DBTimestamp?

    public init(id: Int, slug: String, type: RecordType = .artifact, title: String? = nil, url: String? = nil,
                isCurated: Bool = false, summary: String? = nil, content: String? = nil, notes: String? = nil,
                source: RecordSource? = nil, recordCreatedAt: DBTimestamp, recordUpdatedAt: DBTimestamp? = nil,
                contentCreatedAt: DBTimestamp? = nil, contentUpdatedAt: DBTimestamp? = nil) {
        self.id = id
        self.slug = slug
        self.type = type
        self.title = title
        self.url = url
        self.isCurated = isCurated
        self.summary = summary
        self.content = content
        self.notes = notes
        self.source = source
        self.recordCreatedAt = recordCreatedAt
        self.recordUpdatedAt = recordUpdatedAt ?? recordCreatedAt
        self.contentCreatedAt = contentCreatedAt
        self.contentUpdatedAt = contentUpdatedAt
    }

    /// The URL's host without a leading `www.`, for "at example.com"; nil without a parseable URL.
    public var domain: String? { url.flatMap(displayDomain) }
}

/// A row of `POST /records` and the search endpoints (the server's ListRow): the record's columns except
/// `contentUpdatedAt`, its media, its creation, description and containment outgoing links with a slim target, and
/// every incoming link's predicate alone. Search rows add `score`.
public struct ListRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var slug: String
    public var title: String?
    public var url: String?
    public var type: RecordType
    public var content: String?
    public var summary: String?
    public var recordCreatedAt: DBTimestamp
    public var recordUpdatedAt: DBTimestamp
    public var contentCreatedAt: DBTimestamp?
    public var notes: String?
    public var isCurated: Bool
    public var source: RecordSource?
    public var media: [Media]
    public var outgoingLinks: [OutgoingLink]
    public var incomingLinks: [IncomingLink]
    /// Hybrid search's fused rank score (semantic search's cosine score); nil in plain lists.
    public var score: Double?

    public struct OutgoingLink: Codable, Hashable, Sendable {
        public var predicate: Predicate
        public var target: RecordRef

        public init(predicate: Predicate, target: RecordRef) {
            self.predicate = predicate
            self.target = target
        }
    }

    /// An incoming link carries only its predicate: no ids, no source.
    public struct IncomingLink: Codable, Hashable, Sendable {
        public var predicate: Predicate

        public init(predicate: Predicate) {
            self.predicate = predicate
        }
    }

    public init(id: Int, slug: String, title: String? = nil, url: String? = nil, type: RecordType = .artifact,
                content: String? = nil, summary: String? = nil, recordCreatedAt: DBTimestamp,
                recordUpdatedAt: DBTimestamp? = nil, contentCreatedAt: DBTimestamp? = nil, notes: String? = nil,
                isCurated: Bool = false, source: RecordSource? = nil, media: [Media] = [],
                outgoingLinks: [OutgoingLink] = [], incomingLinks: [IncomingLink] = [], score: Double? = nil) {
        self.id = id
        self.slug = slug
        self.title = title
        self.url = url
        self.type = type
        self.content = content
        self.summary = summary
        self.recordCreatedAt = recordCreatedAt
        self.recordUpdatedAt = recordUpdatedAt ?? recordCreatedAt
        self.contentCreatedAt = contentCreatedAt
        self.notes = notes
        self.isCurated = isCurated
        self.source = source
        self.media = media
        self.outgoingLinks = outgoingLinks
        self.incomingLinks = incomingLinks
        self.score = score
    }

    /// A row for a record the list doesn't hold yet (one just created), with no media or links until the next load.
    public init(_ record: Record) {
        self.init(id: record.id, slug: record.slug, recordCreatedAt: record.recordCreatedAt)
        merge(record)
    }

    /// Takes every column `record` has (as `PUT /record` returned it) and keeps this row's media, links and score,
    /// which a save doesn't change and doesn't return.
    public mutating func merge(_ record: Record) {
        id = record.id
        slug = record.slug
        title = record.title
        url = record.url
        type = record.type
        content = record.content
        summary = record.summary
        recordCreatedAt = record.recordCreatedAt
        recordUpdatedAt = record.recordUpdatedAt
        contentCreatedAt = record.contentCreatedAt
        notes = record.notes
        isCurated = record.isCurated
        source = record.source
    }

    public func merging(_ record: Record) -> ListRecord {
        var row = self
        row.merge(record)
        return row
    }

    /// The URL's host without a leading `www.`, for "at example.com"; nil without a parseable URL.
    public var domain: String? { url.flatMap(displayDomain) }

    /// The first `created_by` target: "by <creator>" on a card.
    public var creator: RecordRef? { targets(.createdBy).first }

    /// The first containment parent (`contained_by`, else `quotes`), as the web's card picks it.
    public var parent: RecordRef? {
        outgoingLinks.first { $0.predicate == .containedBy || $0.predicate == .quotes }?.target
    }

    /// Incoming containment links: the "N HIGHLIGHTS" chip (the web's `childrenCount`).
    public var childCount: Int {
        incomingLinks.count(where: { $0.predicate.type == .containment })
    }

    /// Targets of the outgoing links with `predicate`, in the server's order.
    public func targets(_ predicate: Predicate) -> [RecordRef] {
        outgoingLinks.filter { $0.predicate == predicate }.map(\.target)
    }

    /// Targets of the outgoing links whose predicate is of `type`. The web's card shows `.description` targets
    /// (formats and tags) as `#tags`.
    public func targets(ofType type: PredicateType) -> [RecordRef] {
        outgoingLinks.filter { $0.predicate.type == type }.map(\.target)
    }
}

/// The slim record a list row's outgoing link points at.
public struct RecordRef: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String?
    public var slug: String

    public init(id: Int, title: String?, slug: String) {
        self.id = id
        self.title = title
        self.slug = slug
    }
}

/// `GET /record/:id`: the record, every outgoing link (all predicates, each with its full target but without the
/// link's own id or notes), its media and its archive (at most one). Record fields read straight through:
/// `detail.title` is `detail.record.title`.
@dynamicMemberLookup
public struct RecordDetail: Codable, Hashable, Sendable, Identifiable {
    public var record: Record
    public var outgoingLinks: [OutgoingLink]
    public var media: [Media]
    public var archives: [Archive]

    public struct OutgoingLink: Codable, Hashable, Sendable {
        public var predicate: Predicate
        public var target: Record

        public init(predicate: Predicate, target: Record) {
            self.predicate = predicate
            self.target = target
        }
    }

    public init(record: Record, outgoingLinks: [OutgoingLink] = [], media: [Media] = [], archives: [Archive] = []) {
        self.record = record
        self.outgoingLinks = outgoingLinks
        self.media = media
        self.archives = archives
    }

    private enum CodingKeys: String, CodingKey {
        case outgoingLinks, media, archives
    }

    /// The record's columns and the relations share one JSON object.
    public init(from decoder: any Decoder) throws {
        record = try Record(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outgoingLinks = try container.decode([OutgoingLink].self, forKey: .outgoingLinks)
        media = try container.decode([Media].self, forKey: .media)
        archives = try container.decode([Archive].self, forKey: .archives)
    }

    public func encode(to encoder: any Encoder) throws {
        try record.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outgoingLinks, forKey: .outgoingLinks)
        try container.encode(media, forKey: .media)
        try container.encode(archives, forKey: .archives)
    }

    public var id: Int { record.id }

    public subscript<Value>(dynamicMember keyPath: KeyPath<Record, Value>) -> Value {
        record[keyPath: keyPath]
    }

    /// The first `created_by` target: the detail's "by <creator>".
    public var creator: Record? { targets(.createdBy).first }

    public func targets(_ predicate: Predicate) -> [Record] {
        outgoingLinks.filter { $0.predicate == predicate }.map(\.target)
    }
}

/// A `media` row (MediaSelect). `url` is relative to the server (`/uploads/images/<uuid>.jpg`).
public struct Media: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var recordId: Int?
    public var url: String
    public var altText: String?
    /// The MIME top-level type: "image", "video", "application" (PDFs), …
    public var type: String?
    public var contentTypeString: String
    public var fileSize: Int?
    public var width: Int?
    public var height: Int?
    public var recordCreatedAt: DBTimestamp
    public var recordUpdatedAt: DBTimestamp

    public init(id: Int, recordId: Int?, url: String, altText: String? = nil, type: String?,
                contentTypeString: String, fileSize: Int? = nil, width: Int? = nil, height: Int? = nil,
                recordCreatedAt: DBTimestamp, recordUpdatedAt: DBTimestamp? = nil) {
        self.id = id
        self.recordId = recordId
        self.url = url
        self.altText = altText
        self.type = type
        self.contentTypeString = contentTypeString
        self.fileSize = fileSize
        self.width = width
        self.height = height
        self.recordCreatedAt = recordCreatedAt
        self.recordUpdatedAt = recordUpdatedAt ?? recordCreatedAt
    }

    public var isImage: Bool {
        type == "image" || contentTypeString.lowercased().hasPrefix("image/")
    }

    /// `url` resolved against the server's origin; an absolute URL is returned as it is.
    public func url(relativeTo server: URL) -> URL? {
        URL(string: url, relativeTo: server)?.absoluteURL
    }
}

/// An `archives` row (ArchiveSelect): a local amber snapshot of the record's page.
public struct Archive: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var recordId: Int
    public var url: String
    public var path: String?
    public var status: Status
    public var title: String?
    public var error: String?
    public var archivedAt: DBTimestamp
    public var recordCreatedAt: DBTimestamp
    public var recordUpdatedAt: DBTimestamp

    public struct Status: OpenEnum {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let pending: Status = "pending"
        public static let ok: Status = "ok"
        public static let failed: Status = "failed"
        public static let known: [Status] = [.pending, .ok, .failed]
    }

    public init(id: Int, recordId: Int, url: String, path: String? = nil, status: Status, title: String? = nil,
                error: String? = nil, archivedAt: DBTimestamp, recordCreatedAt: DBTimestamp,
                recordUpdatedAt: DBTimestamp? = nil) {
        self.id = id
        self.recordId = recordId
        self.url = url
        self.path = path
        self.status = status
        self.title = title
        self.error = error
        self.archivedAt = archivedAt
        self.recordCreatedAt = recordCreatedAt
        self.recordUpdatedAt = recordUpdatedAt ?? recordCreatedAt
    }
}

/// A `links` row (LinkSelect): what `PUT /link` and `DELETE /link/:id` return. Stored links are always canonical; the
/// server flips a non-canonical predicate (and the ends) on write.
///
/// SwiftUI declares a `Link` view too: a file importing both writes `EnchiridionKit.Link` or `SwiftUI.Link`, or adds
/// `import struct EnchiridionKit.Link` to make this one win there.
public struct Link: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var sourceId: Int
    public var targetId: Int
    public var predicate: Predicate
    public var notes: String?
    public var recordCreatedAt: DBTimestamp
    public var recordUpdatedAt: DBTimestamp

    public init(id: Int, sourceId: Int, targetId: Int, predicate: Predicate, notes: String? = nil,
                recordCreatedAt: DBTimestamp, recordUpdatedAt: DBTimestamp? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.targetId = targetId
        self.predicate = predicate
        self.notes = notes
        self.recordCreatedAt = recordCreatedAt
        self.recordUpdatedAt = recordUpdatedAt ?? recordCreatedAt
    }
}

/// `GET /record/:id/links`: every link touching the record, both ways, with the far end's title and slug. The nested
/// `target`/`source` have no id: use the link's `targetId`/`sourceId`. Link fields read straight through.
public struct LinksBundle: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var outgoingLinks: [OutgoingLink]
    public var incomingLinks: [IncomingLink]

    public init(id: Int, outgoingLinks: [OutgoingLink] = [], incomingLinks: [IncomingLink] = []) {
        self.id = id
        self.outgoingLinks = outgoingLinks
        self.incomingLinks = incomingLinks
    }

    @dynamicMemberLookup
    public struct OutgoingLink: Codable, Hashable, Sendable, Identifiable {
        public var link: Link
        public var target: Target

        public struct Target: Codable, Hashable, Sendable {
            public var title: String?
            public var slug: String

            public init(title: String?, slug: String) {
                self.title = title
                self.slug = slug
            }
        }

        public init(link: Link, target: Target) {
            self.link = link
            self.target = target
        }

        private enum CodingKeys: String, CodingKey { case target }

        public init(from decoder: any Decoder) throws {
            link = try Link(from: decoder)
            target = try decoder.container(keyedBy: CodingKeys.self).decode(Target.self, forKey: .target)
        }

        public func encode(to encoder: any Encoder) throws {
            try link.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(target, forKey: .target)
        }

        public var id: Int { link.id }

        public subscript<Value>(dynamicMember keyPath: KeyPath<Link, Value>) -> Value {
            link[keyPath: keyPath]
        }
    }

    @dynamicMemberLookup
    public struct IncomingLink: Codable, Hashable, Sendable, Identifiable {
        public var link: Link
        public var source: Source

        public struct Source: Codable, Hashable, Sendable {
            public var title: String?
            public var slug: String
            /// The web shows it for an untitled source (a highlight).
            public var content: String?

            public init(title: String?, slug: String, content: String? = nil) {
                self.title = title
                self.slug = slug
                self.content = content
            }
        }

        public init(link: Link, source: Source) {
            self.link = link
            self.source = source
        }

        private enum CodingKeys: String, CodingKey { case source }

        public init(from decoder: any Decoder) throws {
            link = try Link(from: decoder)
            source = try decoder.container(keyedBy: CodingKeys.self).decode(Source.self, forKey: .source)
        }

        public func encode(to encoder: any Encoder) throws {
            try link.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(source, forKey: .source)
        }

        public var id: Int { link.id }

        public subscript<Value>(dynamicMember keyPath: KeyPath<Link, Value>) -> Value {
            link[keyPath: keyPath]
        }
    }
}

/// The host of `url` without a leading `www.` (the web's `getOriginOfUrl`, which strips the first `www.` anywhere;
/// only a leading one is meant).
func displayDomain(_ url: String) -> String? {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let host = URLComponents(string: trimmed)?.host, !host.isEmpty else { return nil }
    let lowered = host.lowercased()
    return lowered.hasPrefix("www.") ? String(lowered.dropFirst(4)) : lowered
}

/// A row of `GET /record/:id/similar`: a record near the asked one by embedding, records already linked to it left
/// out, with the cosine similarity (`score`) and the server's reasons ("50% similar by content").
public struct SimilarRecord: Codable, Hashable, Sendable, Identifiable {
    public var record: Record
    public var score: Double
    public var reasons: [String]

    public init(record: Record, score: Double, reasons: [String] = []) {
        self.record = record
        self.score = score
        self.reasons = reasons
    }

    public var id: Int { record.id }
}
