import Foundation

/// The body of `PUT /record`, which creates (no `id`) or updates (an `id`) a record.
///
/// The server updates only the keys present and clears a key sent as `null`, so every field this sends is encoded
/// explicitly, `null` included: a field emptied in the editor must clear. A create sends every field. An update
/// sends only the fields it changes (`only(_:)`), so a column changed elsewhere since this copy was loaded is never
/// written back stale. `id` is left out when nil, because that is what makes the request a create. `slug` is
/// required on updates too. The server ignores keys it doesn't know and never derives a slug.
public struct RecordInput: Encodable, Hashable, Sendable {
    public var id: Int?
    public var slug: String
    public var type: RecordType
    public var title: String?
    public var url: String?
    public var isCurated: Bool
    public var summary: String?
    public var content: String?
    public var notes: String?
    public var source: RecordSource?
    /// The fields sent besides `id` and `slug`; nil sends all of them.
    public var fields: Set<Field>?

    /// The editable columns, each of which an update may send or leave out.
    public enum Field: String, CaseIterable, Hashable, Sendable {
        case type, title, url, isCurated, summary, content, notes, source
    }

    public init(id: Int? = nil, slug: String, type: RecordType = .artifact, title: String? = nil, url: String? = nil,
                isCurated: Bool = false, summary: String? = nil, content: String? = nil, notes: String? = nil,
                source: RecordSource? = nil, fields: Set<Field>? = nil) {
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
        self.fields = fields
    }

    /// This input sending only `fields` (besides `id` and `slug`).
    public func only(_ fields: Set<Field>) -> RecordInput {
        var input = self
        input.fields = fields
        return input
    }

    /// The fields whose values differ from `other`'s: what an update from `other` to this has to send.
    public func fieldsDiffering(from other: RecordInput) -> Set<Field> {
        Set(Field.allCases.filter { field in
            switch field {
            case .type: type != other.type
            case .title: title != other.title
            case .url: url != other.url
            case .isCurated: isCurated != other.isCurated
            case .summary: summary != other.summary
            case .content: content != other.content
            case .notes: notes != other.notes
            case .source: source != other.source
            }
        })
    }

    /// Whether the body carries `field`.
    public func sends(_ field: Field) -> Bool {
        fields?.contains(field) ?? true
    }

    /// An update that resends `record` as it is; change fields before saving.
    public init(_ record: Record) {
        self.init(id: record.id, slug: record.slug, type: record.type, title: record.title, url: record.url,
                  isCurated: record.isCurated, summary: record.summary, content: record.content,
                  notes: record.notes, source: record.source)
    }

    /// An update that resends a list row's editable fields as they are.
    public init(_ row: ListRecord) {
        self.init(id: row.id, slug: row.slug, type: row.type, title: row.title, url: row.url,
                  isCurated: row.isCurated, summary: row.summary, content: row.content, notes: row.notes,
                  source: row.source)
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, type, title, url, isCurated, summary, content, notes, source
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(slug, forKey: .slug)
        if sends(.type) { try container.encode(type, forKey: .type) }
        if sends(.title) { try container.encode(title, forKey: .title) }
        if sends(.url) { try container.encode(url, forKey: .url) }
        if sends(.isCurated) { try container.encode(isCurated, forKey: .isCurated) }
        if sends(.summary) { try container.encode(summary, forKey: .summary) }
        if sends(.content) { try container.encode(content, forKey: .content) }
        if sends(.notes) { try container.encode(notes, forKey: .notes) }
        if sends(.source) { try container.encode(source, forKey: .source) }
    }
}

/// The body of `PUT /link`. Without `id` it inserts, idempotently on (source, target, predicate); with one it
/// updates that link. A non-canonical predicate is stored flipped. Nil fields are left out (the server treats a
/// missing `notes` as null).
public struct LinkInput: Encodable, Hashable, Sendable {
    public var id: Int?
    public var sourceId: Int
    public var targetId: Int
    public var predicate: Predicate
    public var notes: String?

    public init(id: Int? = nil, sourceId: Int, targetId: Int, predicate: Predicate, notes: String? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.targetId = targetId
        self.predicate = predicate
        self.notes = notes
    }
}

/// The body of `POST /records` (`ListRecordsInputSchema`). Nil fields are left out and take the server's defaults:
/// limit 100, offset 0, newest `recordCreatedAt` first.
public struct ListQuery: Encodable, Hashable, Sendable {
    public var filters: Filters
    public var limit: Int?
    public var offset: Int?
    public var orderBy: [Order]?

    public struct Filters: Encodable, Hashable, Sendable {
        public var type: RecordType?
        public var isCurated: Bool?
        /// Drops untitled records that have a containment parent (Readwise highlights), as the web's index does.
        public var hideUntitledChildren: Bool?
        /// `LIKE %text%` over title, slug, content, summary and notes.
        public var text: String?

        public init(type: RecordType? = nil, isCurated: Bool? = nil, hideUntitledChildren: Bool? = nil,
                    text: String? = nil) {
            self.type = type
            self.isCurated = isCurated
            self.hideUntitledChildren = hideUntitledChildren
            self.text = text
        }
    }

    /// The server sorts every field as lowercased text, so `id` sorts as a string ("99" after "100").
    public struct Order: Encodable, Hashable, Sendable {
        public var field: Field
        public var direction: Direction

        public enum Field: String, Encodable, Hashable, Sendable, CaseIterable {
            case recordUpdatedAt, recordCreatedAt, title, contentCreatedAt, contentUpdatedAt, id, slug, type
        }

        public enum Direction: String, Encodable, Hashable, Sendable {
            case asc, desc
        }

        public init(_ field: Field, _ direction: Direction) {
            self.field = field
            self.direction = direction
        }
    }

    public init(filters: Filters = Filters(), limit: Int? = nil, offset: Int? = nil, orderBy: [Order]? = nil) {
        self.filters = filters
        self.limit = limit
        self.offset = offset
        self.orderBy = orderBy
    }

    /// The web index's request: everything at once, highlights folded into their parents, newest first. The slug
    /// tiebreak makes the order total (hundreds of imported rows share one `recordCreatedAt`).
    public static let index = ListQuery(
        filters: Filters(hideUntitledChildren: true),
        limit: 100_000,
        orderBy: [Order(.recordCreatedAt, .desc), Order(.slug, .asc)]
    )

    /// The index's first row alone: how the app tells, cheaply, that a record was added elsewhere (a share, the web).
    public static let newest = ListQuery(
        filters: Filters(hideUntitledChildren: true),
        limit: 1,
        orderBy: [Order(.recordCreatedAt, .desc), Order(.slug, .asc)]
    )
}
