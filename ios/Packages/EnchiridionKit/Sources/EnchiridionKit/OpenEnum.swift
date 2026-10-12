import Foundation

/// A string enum the server may grow. Unknown values decode and round-trip instead of failing the whole response;
/// `known` lists this build's values. Each one encodes as its bare string.
public protocol OpenEnum: RawRepresentable<String>, Codable, Hashable, Sendable, ExpressibleByStringLiteral,
    CustomStringConvertible {
    init(rawValue: String)
    static var known: [Self] { get }
}

extension OpenEnum {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public var description: String { rawValue }
    public var isKnown: Bool { Self.known.contains(self) }
}

/// `records.type`.
public struct RecordType: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let artifact: RecordType = "artifact"
    public static let concept: RecordType = "concept"
    public static let entity: RecordType = "entity"
    /// In the order the web's filter chips list them.
    public static let known: [RecordType] = [.artifact, .concept, .entity]

    /// "Artifact", "Concept", "Entity"; an unknown type shows its own name, capitalized.
    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// `records.source`: where a record came from. The column is nullable, so `Record.source` is optional.
public struct RecordSource: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let manual: RecordSource = "manual"
    public static let readwise: RecordSource = "readwise"
    public static let twitter: RecordSource = "twitter"
    public static let known: [RecordSource] = [.manual, .readwise, .twitter]

    /// "Manual", "Readwise", "Twitter"; an unknown source shows its own name, capitalized.
    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}
