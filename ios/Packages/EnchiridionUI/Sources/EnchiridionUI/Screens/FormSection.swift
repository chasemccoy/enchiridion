import SwiftUI

/// A titled group of rows on one card, as Settings and the record editor draw them: the title in `groupLabel`, muted;
/// the rows on `surface` with a `border` hairline and the card radius, each padded, a hairline between them; an
/// optional footer in `textDimmed`. Plain stacks in a scroll view rather than a `Form`, so every color is the
/// palette's and nothing is the grouped-list system style.
struct FormSection<Rows: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder let rows: () -> Rows

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder rows: @escaping () -> Rows) {
        self.title = title
        self.footer = footer
        self.rows = rows
    }

    var body: some View {
        let shape = Radius.shape(Radius.card)
        VStack(alignment: .leading, spacing: Space.metaGap) {
            if let title {
                Text(verbatim: title)
                    .font(Typography.groupLabel)
                    .foregroundStyle(Palette.textMuted)
                    .padding(.horizontal, Metrics.formRowPadding.leading)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: rows()) { subviews in
                    ForEach(subviews.indices, id: \.self) { index in
                        if index > 0 {
                            Palette.border.view
                                .frame(height: Metrics.formRule)
                                .padding(.leading, Metrics.formRowPadding.leading)
                        }
                        subviews[index]
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Metrics.formRowPadding)
                    }
                }
            }
            .font(Typography.field)
            .foregroundStyle(Palette.text)
            .background(Palette.surface, in: shape)
            .overlay { shape.strokeBorder(Palette.border, lineWidth: Metrics.cardBorder) }
            if let footer {
                Text(verbatim: footer)
                    .font(Typography.stateMessage)
                    .foregroundStyle(Palette.textDimmed)
                    .wrapsFully()
                    .padding(.horizontal, Metrics.formRowPadding.leading)
            }
        }
    }
}

/// A label and its value on one line: the label in `text`, the value in `textMuted`, trailing (selectable).
struct FormValueRow: View {
    let label: String
    let value: String
    var monospaced = false

    init(_ label: String, _ value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.metaGap) {
            Text(verbatim: label)
                .foregroundStyle(Palette.text)
            Spacer(minLength: Space.metaGap)
            Text(verbatim: value)
                .font(monospaced ? Typography.mono : Typography.field)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
