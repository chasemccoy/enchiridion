import SwiftUI

/// A month above its rows, as a plain list's section heading: "September 2026 (5)", left-aligned, semibold and muted.
public struct MonthHeader: View {
    let title: String

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
        Text(verbatim: title)
            .font(Typography.monthHeading)
            .foregroundStyle(Palette.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
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
