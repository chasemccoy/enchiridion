import SwiftUI

/// Shape: the web's radius scale (Nuxt UI over a 6 px `--ui-radius`). Every rounded rectangle is `.continuous`, the
/// nearest SwiftUI has to the web's `corner-shape: superellipse(1.333)`; build them with `Radius.shape(_:)`.
public enum Radius {
    /// Cards, linked-record rows (`--radius-lg`).
    public static let card: CGFloat = 12
    /// Badges on cards (`sm`).
    public static let badgeSmall: CGFloat = 6
    /// Badges in the detail (`md`).
    public static let badge: CGFloat = 9
    /// Buttons, filter chips, the parent chip, metadata rows (`md`).
    public static let button: CGFloat = 9
    /// A card's image (`md`).
    public static let image: CGFloat = 9
    /// A note's bubble.
    public static let noteBubble: CGFloat = 10
    /// Inline code and `==marks==` (`sm`).
    public static let small: CGFloat = 6
    /// A code block (`md`).
    public static let codeBlock: CGFloat = 9

    /// A continuous rounded rectangle.
    public static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// Fully rounded: the highlight chip, the nav pill.
    public static var pill: Capsule { Capsule(style: .continuous) }
}

/// Space, from the web's measured gaps and paddings.
public enum Space {
    /// The list's and the detail's side margins on a phone (the web's list padding and narrow detail padding).
    public static let margin: CGFloat = 16
    /// Inside a card.
    public static let cardPadding: CGFloat = 12
    /// Between a card's slots, and between cards in the list.
    public static let cardGap: CGFloat = 6
    /// Between the month groups of the list.
    public static let monthGap: CGFloat = 32
    /// Between a month header and its first card.
    public static let afterMonthHeader: CGFloat = 8
    /// Between the detail's blocks: badges, title, content, metadata, actions.
    public static let detailGap: CGFloat = 16
    /// Between badges in a row, and between the meta row's items vertically when they wrap.
    public static let badgeGap: CGFloat = 6
    /// Between the meta row's items.
    public static let metaGap: CGFloat = 8
    /// Between the meta row's wrapped lines.
    public static let metaLineGap: CGFloat = 2
    /// Between an icon and its label (badges, chips, metadata labels).
    public static let iconGap: CGFloat = 4
    /// Between filter chips.
    public static let chipGap: CGFloat = 4
    /// Between Markdown blocks (0.6em of the 13 pt body).
    public static let block: CGFloat = 8
    /// Between the items of one list in Markdown (0.25em).
    public static let listItem: CGFloat = 3
    /// Between the actions of a row (Edit, Delete, the Curated switch).
    public static let actions: CGFloat = 8
    /// Between a stacked state's lines (an error, not-allowed).
    public static let state: CGFloat = 8
}

/// The few component sizes the web fixes, in one place.
public enum Metrics {
    /// The card's hairline (the web's 0.5 px border).
    public static let cardBorder: CGFloat = 0.5
    /// A row's image: its height, and the point of the image kept in view when it is cropped (the web's
    /// `object-position: 50% 25%`).
    public static let cardImageHeight: CGFloat = 150
    public static let cardImageFocus = UnitPoint(x: 0.5, y: 0.25)
    /// The note bubble's padding.
    public static let notePadding = EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
    /// Badges: padding and icon size, small (cards) and regular (detail).
    public static let badgeSmallPadding = EdgeInsets(top: 3, leading: 5, bottom: 3, trailing: 5)
    public static let badgePadding = EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)
    public static let badgeIcon: CGFloat = 12
    /// The highlight chip's padding.
    public static let highlightChipPadding = EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6)
    /// Filter chips (the web's xs buttons): height, padding, icon size.
    public static let chipHeight: CGFloat = 24
    public static let chipPadding = EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
    public static let chipIcon: CGFloat = 14
    /// Raised neutral buttons (Edit, Delete record): height and padding.
    public static let buttonHeight: CGFloat = 28
    public static let buttonPadding = EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
    /// A sheet's main action.
    public static let prominentButtonHeight: CGFloat = 44
    /// Metadata rows: the label column's width, the gap to the value, and the row's padding.
    public static let metadataLabelWidth: CGFloat = 110
    public static let metadataGap: CGFloat = 12
    public static let metadataPadding = EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0)
    /// A metadata label's icon.
    public static let metadataIcon: CGFloat = 13
    /// The parent chip's padding and icon.
    public static let parentChipPadding = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 12)
    /// Month-header rules.
    public static let rule: CGFloat = 1
    /// A Markdown quote's rule, and its distance from the text (0.75em).
    public static let quoteRule: CGFloat = 2
    public static let quoteGap: CGFloat = 10
    /// A Markdown list's marker column (1.5em) and each nested level's indent.
    public static let listMarker: CGFloat = 18
    public static let listIndent: CGFloat = 18
    /// A Markdown code block's padding.
    public static let codePadding = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
    /// The widest a centered state (an error, not-allowed) gets.
    public static let stateWidth: CGFloat = 320
    /// The detail's readable width (the web's 680 px column).
    public static let detailWidth: CGFloat = 680
}
