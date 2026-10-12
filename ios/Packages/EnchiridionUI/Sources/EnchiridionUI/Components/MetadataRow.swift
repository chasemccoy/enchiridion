import SwiftUI

/// One row of the detail's metadata sheet (Summary, URL, Published, Notes): a fixed label column (13 pt dimmed
/// symbol and 12 pt muted label) beside the value in 14 pt muted text, their first lines on one baseline. At the
/// accessibility text sizes the label sits above the value instead, as the web stacks them on narrow screens.
public struct MetadataRow<Value: View>: View {
    let label: String
    let systemImage: String
    let value: Value
    @ScaledMetric(relativeTo: .caption) private var labelWidth = Metrics.metadataLabelWidth
    @ScaledMetric(relativeTo: .caption) private var iconSize = Metrics.metadataIcon
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ label: String, systemImage: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.systemImage = systemImage
        self.value = value()
    }

    public var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.iconGap))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Metrics.metadataGap))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: Space.badgeGap) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                    .foregroundStyle(Palette.textDimmed)
                    .accessibilityHidden(true)
                Text(verbatim: label)
                    .font(Typography.metadataLabel)
                    .foregroundStyle(Palette.textMuted)
            }
            .frame(width: stacked ? nil : labelWidth, alignment: .leading)
            value
                .font(Typography.metadataValue)
                .foregroundStyle(Palette.textMuted)
                .wrapsFully()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Metrics.metadataPadding)
        .accessibilityElement(children: .combine)
    }
}

extension MetadataRow where Value == MetadataText {
    /// A row whose value is plain, selectable text.
    public init(_ label: String, systemImage: String, text: String) {
        self.init(label, systemImage: systemImage) { MetadataText(text: text) }
    }
}

/// A metadata value as selectable text.
public struct MetadataText: View {
    let text: String

    public var body: some View {
        Text(verbatim: text)
            .textSelection(.enabled)
    }
}

#if DEBUG
#Preview("Metadata rows") {
    VStack(alignment: .leading, spacing: 0) {
        MetadataRow("Summary", systemImage: Symbol.summary,
                    text: "A space opera about an AI who used to be a troop carrier, told in the first person.")
        MetadataRow("URL", systemImage: Symbol.url, text: "https://example.com/ancillary-justice")
        MetadataRow("Published", systemImage: Symbol.published, text: "March 14, 2026")
        MetadataRow("Notes", systemImage: Symbol.notes) {
            Text(verbatim: "Additional notes").foregroundStyle(Palette.textDimmed)
        }
    }
    .padding(Space.margin)
    .previewRoot()
}
#endif
