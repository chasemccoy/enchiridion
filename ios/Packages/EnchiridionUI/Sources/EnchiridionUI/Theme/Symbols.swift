import EnchiridionKit

/// SF Symbols standing in for the web's lucide icons (design map §6), so every screen draws the same glyph for the
/// same thing.
public enum Symbol {
    /// "Needs curating" (`inbox`).
    public static let needsCuration = "tray"
    /// The captured date badge (`calendar-arrow-down`).
    public static let captured = "calendar.badge.clock"
    /// The record id badge (`hash`).
    public static let recordID = "number"
    /// "from" a parent (`workflow`).
    public static let parent = "flowchart"
    /// "by" a creator (`user-pen`).
    public static let creator = "person"
    /// The parent chip above a search hit (`corner-down-right`).
    public static let parentChip = "arrow.turn.down.right"
    /// Metadata rows (`text`, `link`, `calendar`, `pencil-line`).
    public static let summary = "text.alignleft"
    public static let url = "link"
    public static let published = "calendar"
    public static let notes = "pencil.line"
    /// Open the source URL (`external-link`).
    public static let openURL = "arrow.up.right.square"
    public static let delete = "trash"
    public static let edit = "pencil"
    public static let add = "plus"
    public static let settings = "gearshape"
    public static let search = "magnifyingglass"
    public static let copy = "doc.on.doc"
    public static let retry = "arrow.clockwise"
    /// Curate / uncurate in swipe actions and menus.
    public static let curate = "checkmark.circle"
    public static let uncurate = "tray.and.arrow.down"
    /// Linked-record predicates for children (`quote`, `indent-increase`).
    public static let quote = "quote.opening"
    public static let part = "increase.indent"
    /// An archived copy (`archive`).
    public static let archive = "archivebox"
    /// The web's fallback (`circle`).
    public static let fallback = "circle"
}

extension RecordType {
    /// `shippingbox`, `brain`, `person.2` (the web's `box`, `brain`, `users`); `circle` for a type this build doesn't
    /// know.
    public var symbolName: String {
        switch self {
        case .artifact: "shippingbox"
        case .concept: "brain"
        case .entity: "person.2"
        default: Symbol.fallback
        }
    }
}

extension RecordSource {
    /// `book` for Readwise; `bubble.left` for Twitter, which has no SF Symbol; nil for a manual record, which shows
    /// no source. `circle` for a source this build doesn't know.
    public var symbolName: String? {
        switch self {
        case .manual: nil
        case .readwise: "book"
        case .twitter: "bubble.left"
        default: Symbol.fallback
        }
    }
}
