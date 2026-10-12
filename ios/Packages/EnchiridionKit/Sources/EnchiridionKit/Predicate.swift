import Foundation

/// A link's predicate slug, as the server sends it (`links.predicate`). Open: a slug this build doesn't know decodes
/// and renders by its own name. There is no predicates endpoint, so the vocabulary is embedded below, copied from
/// `shared/types/predicates.ts`.
///
/// Foundation declares a generic `Predicate` too. Member expressions (`Predicate.createdBy`, `.hasFormat`) resolve
/// on their own, but a file that also imports Foundation (or SwiftUI) and names this type in a declaration gets
/// "'Predicate' is ambiguous for type lookup": add `import struct EnchiridionKit.Predicate` (a scoped import outranks
/// a whole-module one) or write `EnchiridionKit.Predicate`.
public struct Predicate: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    // Creation
    public static let createdBy: Predicate = "created_by"
    public static let creatorOf: Predicate = "creator_of"
    public static let via: Predicate = "via"
    public static let sourceFor: Predicate = "source_for"
    public static let editedBy: Predicate = "edited_by"
    public static let editorOf: Predicate = "editor_of"
    // Containment
    public static let containedBy: Predicate = "contained_by"
    public static let contains: Predicate = "contains"
    public static let quotes: Predicate = "quotes"
    public static let quotedIn: Predicate = "quoted_in"
    // Description
    public static let hasFormat: Predicate = "has_format"
    public static let formatOf: Predicate = "format_of"
    public static let taggedWith: Predicate = "tagged_with"
    public static let tagOf: Predicate = "tag_of"
    // Reference
    public static let references: Predicate = "references"
    public static let referencedBy: Predicate = "referenced_by"
    public static let about: Predicate = "about"
    public static let subjectOf: Predicate = "subject_of"
    // Association and identity (both self-inverse)
    public static let relatedTo: Predicate = "related_to"
    public static let sameAs: Predicate = "same_as"

    public static let known: [Predicate] = vocabulary.map(\.slug)

    /// One row of the vocabulary.
    public struct Definition: Hashable, Sendable {
        public let slug: Predicate
        /// Lowercase, as the web shows it: "created by".
        public let name: String
        public let type: PredicateType
        /// Only creation predicates have one: "creator", "referrer", "editor".
        public let role: String?
        public let inverse: Predicate
        /// Only canonical predicates are stored; the server flips a non-canonical one to its inverse on write.
        public let canonical: Bool
    }

    /// The 20 predicates, in the order of `PREDICATES` in `shared/types/predicates.ts`.
    public static let vocabulary: [Definition] = [
        Definition(slug: .createdBy, name: "created by", type: .creation, role: "creator", inverse: .creatorOf, canonical: true),
        Definition(slug: .creatorOf, name: "creator of", type: .creation, role: "creator", inverse: .createdBy, canonical: false),
        Definition(slug: .via, name: "via", type: .creation, role: "referrer", inverse: .sourceFor, canonical: true),
        Definition(slug: .sourceFor, name: "source for", type: .creation, role: "referrer", inverse: .via, canonical: false),
        Definition(slug: .editedBy, name: "edited by", type: .creation, role: "editor", inverse: .editorOf, canonical: true),
        Definition(slug: .editorOf, name: "editor of", type: .creation, role: "editor", inverse: .editedBy, canonical: false),
        Definition(slug: .containedBy, name: "contained by", type: .containment, role: nil, inverse: .contains, canonical: true),
        Definition(slug: .contains, name: "contains", type: .containment, role: nil, inverse: .containedBy, canonical: false),
        Definition(slug: .quotes, name: "quotes", type: .containment, role: nil, inverse: .quotedIn, canonical: true),
        Definition(slug: .quotedIn, name: "quoted in", type: .containment, role: nil, inverse: .quotes, canonical: false),
        Definition(slug: .hasFormat, name: "has format", type: .description, role: nil, inverse: .formatOf, canonical: true),
        Definition(slug: .formatOf, name: "format of", type: .description, role: nil, inverse: .hasFormat, canonical: false),
        Definition(slug: .taggedWith, name: "tagged with", type: .description, role: nil, inverse: .tagOf, canonical: true),
        Definition(slug: .tagOf, name: "tag of", type: .description, role: nil, inverse: .taggedWith, canonical: false),
        Definition(slug: .references, name: "references", type: .reference, role: nil, inverse: .referencedBy, canonical: true),
        Definition(slug: .referencedBy, name: "referenced by", type: .reference, role: nil, inverse: .references, canonical: false),
        Definition(slug: .about, name: "about", type: .reference, role: nil, inverse: .subjectOf, canonical: true),
        Definition(slug: .subjectOf, name: "subject of", type: .reference, role: nil, inverse: .about, canonical: false),
        Definition(slug: .relatedTo, name: "related to", type: .association, role: nil, inverse: .relatedTo, canonical: true),
        Definition(slug: .sameAs, name: "same as", type: .identity, role: nil, inverse: .sameAs, canonical: true),
    ]

    private static let definitions: [Predicate: Definition] =
        Dictionary(uniqueKeysWithValues: vocabulary.map { ($0.slug, $0) })

    /// The vocabulary row; nil for a slug this build doesn't know.
    public var definition: Definition? { Self.definitions[self] }

    /// The predicate's own name ("created by"); an unknown slug reads with its underscores as spaces.
    public var name: String {
        definition?.name ?? rawValue.replacingOccurrences(of: "_", with: " ")
    }

    /// The predicate read from the other end; self-inverse predicates and unknown slugs are their own inverse.
    public var inverse: Predicate { definition?.inverse ?? self }

    /// nil for an unknown slug, which therefore matches no type (like the web's `isPredicateType`).
    public var type: PredicateType? { definition?.type }

    public var isCanonical: Bool { definition?.canonical ?? false }

    /// The label for a link seen from one of its ends (the web's `useRecordLinks`): an outgoing link reads by its
    /// own name, an incoming one by its inverse's ("created by" on the work is "creator of" on the person).
    public func displayName(_ direction: LinkDirection) -> String {
        switch direction {
        case .outgoing: name
        case .incoming: inverse.name
        }
    }

    public static func ofType(_ type: PredicateType) -> [Predicate] {
        vocabulary.filter { $0.type == type }.map(\.slug)
    }
}

/// `predicateTypes` in `shared/types/predicates.ts`.
public enum PredicateType: String, Hashable, Sendable, CaseIterable {
    case creation, containment, description, association, reference, identity
}

/// Which end of a link a record is on.
public enum LinkDirection: Hashable, Sendable {
    /// The record is the link's source.
    case outgoing
    /// The record is the link's target.
    case incoming
}
