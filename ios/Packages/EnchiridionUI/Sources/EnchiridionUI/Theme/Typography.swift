import SwiftUI

/// Type: the web's sizes mapped onto Dynamic Type styles, so everything scales. Sans is the system font (the web's
/// Public Sans isn't bundled); the serif, Martina Plantijn, is only for the wordmark and the detail title, as on the
/// web. Views take every font from here.
public enum Typography {
    // MARK: Serif

    /// The detail title: 27 pt Martina Plantijn Regular, scaling with `.title` (the web's 1.7rem `TitleField`).
    public static var detailTitle: Font { serif(.regular, size: 27, relativeTo: .title) }
    /// The extra space between a wrapped detail title's lines (the web measures ≈1.43 line height).
    public static let detailTitleLineSpacing: CGFloat = 4
    /// The "Enchiridion" wordmark: 20 pt Martina Plantijn Medium, scaling with `.headline` (a step up from the web's
    /// 1.05rem logo, to hold the bar beside the system's larger controls).
    public static var wordmark: Font { serif(.medium, size: 20, relativeTo: .headline) }

    /// Martina Plantijn at `size`, scaling with `style`; New York at `style` while the face isn't registered
    /// (`FontRegistry`), since `Font.custom` would otherwise fall back to the system sans without a word.
    public static func serif(_ face: FontRegistry.Face = .regular, size: CGFloat,
                             relativeTo style: Font.TextStyle) -> Font {
        if FontRegistry.isAvailable(face) {
            return .custom(face.postScriptName, size: size, relativeTo: style)
        }
        let fallback = Font.system(style, design: .serif)
        return face == .medium ? fallback.weight(.medium) : fallback
    }

    // MARK: Cards

    /// A card's title (16 pt, regular, in `text`).
    public static let cardTitle: Font = .callout
    /// "by Ann Leckie  at example.com" after a card's title (12 pt medium, muted).
    public static let byline: Font = .caption.weight(.medium)
    /// A card's summary or content (13 pt, clamped to 4 lines), and Markdown's body in cards.
    public static let cardBody: Font = .footnote
    /// The extra space between `cardBody` lines (the web sets 1.5 line height on 12.8 px).
    public static let bodyLineSpacing: CGFloat = 2
    /// A card's meta row: date, tags (13 pt, dimmed).
    public static let meta: Font = .footnote
    /// A note's bubble (12 pt, primary).
    public static let note: Font = .caption
    /// "3 HIGHLIGHTS" (10 pt on the web; the smallest Dynamic Type style).
    public static let highlightChip: Font = .caption2
    /// The parent chip above a search hit's title (12 pt medium, muted).
    public static let parentChip: Font = .caption.weight(.medium)

    // MARK: Badges, chips, buttons

    /// Detail badges (12 pt medium).
    public static let badge: Font = .caption.weight(.medium)
    /// Card badges (10 pt medium on the web).
    public static let badgeSmall: Font = .caption2.weight(.medium)
    /// Filter chips and toolbar buttons (12 pt medium).
    public static let chip: Font = .caption.weight(.medium)
    /// Raised neutral buttons: Edit, Delete record (12 pt medium).
    public static let button: Font = .caption.weight(.medium)
    /// A sheet's or card's main action.
    public static let prominentButton: Font = .body.weight(.semibold)

    // MARK: Lists and detail

    /// "September 2026 (5)" between the list's months (12 pt, dimmed).
    public static let monthHeader: Font = .caption
    /// "Linked records" and other section headings (16 pt semibold).
    public static let sectionHeading: Font = .callout.weight(.semibold)
    /// The detail's byline under the title (13 pt, muted).
    public static let detailByline: Font = .footnote
    /// A metadata row's label: Summary, URL, Published, Notes (12 pt, muted).
    public static let metadataLabel: Font = .caption
    /// A metadata row's value (14 pt, muted).
    public static let metadataValue: Font = .subheadline
    /// A linked-records group's label (12 pt medium, muted).
    public static let groupLabel: Font = .caption.weight(.medium)
    /// Record counts and other toolbar text (12 pt, dimmed).
    public static let count: Font = .caption
    /// Device ids and other machine text.
    public static let mono: Font = .footnote.monospaced()
    /// A state's title (an error, an empty list).
    public static let stateTitle: Font = .body.weight(.semibold)
    /// A state's explanation.
    public static let stateMessage: Font = .footnote

    // MARK: Markdown

    /// Markdown headings for a body set in `cardBody`: the web's h1 1.1rem, h2 1rem, h3 and h4 0.9rem over a 0.8rem
    /// body, all weight 600.
    public static func heading(_ level: Int) -> Font {
        switch level {
        case 1: .headline
        case 2: .callout.weight(.semibold)
        default: .subheadline.weight(.semibold)
        }
    }

    /// Code in Markdown set in `cardBody` (the web's 0.75rem `pre`).
    public static let code: Font = .caption.monospaced()

    /// Markdown's body for reading at length (the detail's content): one step up from `cardBody`.
    public static let readingBody: Font = .subheadline
    /// The extra space between `readingBody` lines.
    public static let readingLineSpacing: CGFloat = 3
    /// Code in Markdown set in `readingBody`.
    public static let readingCode: Font = .footnote.monospaced()

    /// Markdown headings over `readingBody`, in the web's proportions.
    public static func readingHeading(_ level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.semibold)
        case 2: .title3.weight(.semibold)
        default: .headline
        }
    }
}
