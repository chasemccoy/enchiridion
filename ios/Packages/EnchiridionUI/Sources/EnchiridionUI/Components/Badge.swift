import EnchiridionKit
import SwiftUI

/// The web's neutral outline badge (UBadge `color="neutral" variant="outline"`): transparent fill, a `border`
/// hairline, muted text, an optional 12 pt SF Symbol, 4 pt apart. `.small` is the card's (10 pt text, 6 pt radius),
/// `.regular` the detail's badge row (12 pt text, 9 pt radius).
///
/// One line at its ideal width, but never wider than it is offered: at accessibility text sizes a long badge (the
/// captured date) wraps inside the row `FlowLayout` gives it instead of running off the screen.
public struct Badge: View {
    public enum Size: Hashable, Sendable {
        case small
        case regular
    }

    let title: String
    let systemImage: String?
    let size: Size
    @ScaledMetric(relativeTo: .caption) private var iconSize = Metrics.badgeIcon
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ title: String, systemImage: String? = nil, size: Size = .regular) {
        self.title = title
        self.systemImage = systemImage
        self.size = size
    }

    public var body: some View {
        let shape = Radius.shape(size == .small ? Radius.badgeSmall : Radius.badge)
        HStack(spacing: Space.iconGap) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                    .accessibilityHidden(true)
            }
            Text(verbatim: title)
        }
        .font(size == .small ? Typography.badgeSmall : Typography.badge)
        .foregroundStyle(Palette.textMuted)
        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        .padding(size == .small ? Metrics.badgeSmallPadding : Metrics.badgePadding)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A record's type as a badge: "Concept" with `brain`. Cards show it only for non-artifacts; the detail always does.
public struct TypeBadge: View {
    let type: RecordType
    let size: Badge.Size

    public init(_ type: RecordType, size: Badge.Size = .regular) {
        self.type = type
        self.size = size
    }

    public var body: some View {
        Badge(type.displayName, systemImage: type.symbolName, size: size)
    }
}

/// "3 HIGHLIGHTS": how many records a card's record contains (its incoming containment links), on a pill with a
/// hairline edge, dimmed.
public struct HighlightChip: View {
    let count: Int

    public init(count: Int) {
        self.count = count
    }

    /// "1 highlight", "3 highlights" (the web's `pluralize`; the chip shows it uppercased).
    public static func label(count: Int) -> String {
        "\(count) \(count == 1 ? "highlight" : "highlights")"
    }

    public var body: some View {
        Text(verbatim: Self.label(count: count).uppercased())
            .font(Typography.highlightChip)
            .foregroundStyle(Palette.textDimmed)
            .lineLimit(1)
            .padding(Metrics.highlightChipPadding)
            .background(Palette.surface, in: Radius.pill)
            .overlay { Radius.pill.strokeBorder(Palette.border, lineWidth: 1) }
            .fixedSize()
            .accessibilityLabel(Text(verbatim: Self.label(count: count)))
    }
}

#if DEBUG
#Preview("Badges") {
    VStack(alignment: .leading, spacing: Space.cardGap) {
        HStack(spacing: Space.badgeGap) {
            Badge("Needs curating", systemImage: Symbol.needsCuration)
            TypeBadge(.artifact)
            Badge("Readwise", systemImage: RecordSource.readwise.symbolName)
        }
        HStack(spacing: Space.badgeGap) {
            Badge("March 14, 2026 at 10:12 AM", systemImage: Symbol.captured)
            Badge("777", systemImage: Symbol.recordID)
        }
        HStack(spacing: Space.metaGap) {
            TypeBadge(.concept, size: .small)
            TypeBadge(.entity, size: .small)
            HighlightChip(count: 1)
            HighlightChip(count: 12)
        }
    }
    .padding(Space.margin)
    .previewRoot()
}
#endif
