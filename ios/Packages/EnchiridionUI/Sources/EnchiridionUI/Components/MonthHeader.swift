import SwiftUI

/// A month between the list's groups: a hairline rule, "September 2026 (5)", a hairline rule (the web's
/// `1fr auto 1fr` grid), 12 pt and dimmed. The label comes first: the rules shrink to nothing before it does, and at
/// accessibility text sizes it wraps onto a second line rather than overflow the row.
public struct MonthHeader: View {
    let title: String
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `title` as it is, when the caller already decided about the count.
    public init(_ title: String) {
        self.title = title
    }

    /// `title`, with " (N)" when the month holds more than four records, as the web does.
    public init(_ title: String, count: Int) {
        self.title = Self.label(title, count: count)
    }

    /// "September 2026 (5)" for a month of more than four records; "September 2026" otherwise.
    public static func label(_ title: String, count: Int) -> String {
        count > 4 ? "\(title) (\(count))" : title
    }

    public var body: some View {
        HStack(spacing: Space.metaGap) {
            rule
            Text(verbatim: title)
                .font(Typography.monthHeader)
                .foregroundStyle(Palette.textDimmed)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            rule
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(.isHeader)
    }

    private var rule: some View {
        Palette.border.view
            .frame(height: Metrics.rule)
            .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Month header") {
    VStack(spacing: Space.monthGap) {
        MonthHeader("September 2026", count: 5)
        MonthHeader("August 2026", count: 3)
    }
    .padding(Space.margin)
    .previewRoot()
}
#endif
