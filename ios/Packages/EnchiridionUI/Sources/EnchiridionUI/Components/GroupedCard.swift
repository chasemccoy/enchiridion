import SwiftUI

/// An iOS-style grouped list for a detail screen (Details, a linked-record group): rows on `surface` inside the card
/// radius and a hairline `border`, separated by one hairline inset to the rows' text. One separator weight and color
/// everywhere, so nothing on the detail draws a second kind of rule.
struct GroupedCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = Radius.shape(Radius.card)
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content()) { rows in
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        RowSeparator()
                    }
                    row
                }
            }
        }
        .background(Palette.surface, in: shape)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: Metrics.cardBorder) }
        .clipShape(shape)
    }
}

/// The hairline between a grouped card's rows, inset to the rows' text.
struct RowSeparator: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Palette.border.view
            .frame(height: 1 / displayScale)
            .padding(.leading, Metrics.groupedRowPadding.leading)
            .accessibilityHidden(true)
    }
}

/// A grouped card's caption: small, muted, above the card, inset to the rows' text.
struct GroupedCardLabel: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(Typography.groupLabel)
            .foregroundStyle(Palette.textMuted)
            .padding(.leading, Metrics.groupedRowPadding.leading)
            .accessibilityAddTraits(.isHeader)
    }
}
