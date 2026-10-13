import EnchiridionKit
import SwiftUI

// Tokens only the screens use, kept beside them so the theme files stay the shared vocabulary. Views still take every
// font, space and size from these namespaces.

extension Typography {
    /// Text typed into a form or the share card, and a form row's label (16 pt).
    static let field: Font = .callout
    /// A linked record's title in the detail (the web's 0.9rem, weight 500).
    static let linkTitle: Font = .subheadline.weight(.medium)
    /// The Curated switch's label (the web's 14 px, weight 500).
    static let toggleLabel: Font = .subheadline.weight(.medium)
    /// The domain heading the share card's preview.
    static let shareDomain: Font = .callout.weight(.semibold)
    // The library's rows take iOS's own list sizes (Mail's), not the web's smaller scale.
    /// A record's title in the library's rows (17 pt semibold, as Mail's sender).
    static let rowTitle: Font = .headline
    /// A row's summary or content (15 pt, as Mail's preview); an untitled record's content leads at `.body`.
    static let rowBody: Font = .subheadline
    static let rowLead: Font = .body
    /// A row's muted line: who or where, when, tags (13 pt).
    static let rowMeta: Font = .footnote
    /// The library's month headings, left-aligned above their rows (15 pt semibold).
    static let monthHeading: Font = .subheadline.weight(.semibold)
}

extension Space {
    /// Between a form's sections (the editor, Settings, the share card's blocks).
    static let formSection: CGFloat = 24
    /// Between the linked-records heading, its groups and their rules (the web's 10 px).
    static let linked: CGFloat = 10
    /// Between the actions row's lines when it wraps (the web's 12 px row gap).
    static let actionLines: CGFloat = 12
}

extension Metrics {
    /// A library row's padding: the page margin at the sides.
    static let rowPadding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    /// The list column on iPad: wide enough for a row's summary and thumbnail, never wider than reads well.
    static let listColumnMin: CGFloat = 320
    static let listColumnIdeal: CGFloat = 380
    static let listColumnMax: CGFloat = 480
    /// The 1 × 16 pt rule between the filter bar's type chips and its curation chip (the web toolbar's divider).
    static let filterDivider = CGSize(width: 1, height: 16)
    /// The filter bar's vertical padding.
    static let filterBarPadding: CGFloat = 6
    /// A form row's padding, and the rule between rows.
    static let formRowPadding = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    static let formRule: CGFloat = 0.5
    /// A boxed text field's padding (the share card's fields).
    static let fieldPadding = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    /// A linked-record row's padding (the web's `RecordLink` row layout, 7 by 10).
    static let linkRowPadding = EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
    /// The detail is wide enough to set linked-record groups beside their label column, as the web does above 768 px.
    static let wideDetail: CGFloat = 520
    /// A grouped card row's padding, and the gap between a group's caption and its card.
    static let groupedRowPadding = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
    static let groupedCaptionGap: CGFloat = 6
    /// The tallest a detail image gets before it is scaled down to fit.
    static let detailImageMaxHeight: CGFloat = 420
    /// The share card's preview icon square, and its widest the card gets on iPad.
    static let sharePreviewIcon: CGFloat = 36
    static let shareCardWidth: CGFloat = 560
}

extension Symbol {
    /// A linked record leads to its own detail.
    static let disclosure = "chevron.forward"
    /// An image that didn't load.
    static let image = "photo"
    /// The share card's preview: a page, or shared text.
    static let page = "doc.text"
    static let text = "text.quote"
    /// "Saved to Enchiridion".
    static let saved = "checkmark.circle.fill"
    /// A save that failed.
    static let failure = "exclamationmark.triangle"
    /// The filter and sort menu: outlined at rest, filled while a filter hides records.
    static let filter = "line.3.horizontal.decrease"
    static let filterOn = "line.3.horizontal.decrease.circle.fill"
    static let allRecords = "square.stack"
    static let sort = "arrow.up.arrow.down"
    static let reset = "arrow.counterclockwise"
    /// The detail's bar: curate (filled once curated), open in the browser, share.
    static let curated = "checkmark.circle.fill"
    static let browser = "safari"
    static let share = "square.and.arrow.up"
    static let more = "ellipsis"
    /// A pending link on the share card: its relationship menu, and removing it.
    static let relationship = "chevron.up.chevron.down"
    static let removeLink = "xmark.circle.fill"
    /// A detail's "Add link", and linking a similar record.
    static let addLink = "link.badge.plus"
    /// A linked record's "Remove link".
    static let unlink = "minus.circle"
}

extension RecordType {
    /// The type as a filter names it: "Artifacts", "Concepts", "Entities".
    var pluralName: String {
        switch self {
        case .artifact: "Artifacts"
        case .concept: "Concepts"
        case .entity: "Entities"
        default: displayName
        }
    }
}
