import EnchiridionKit
import SwiftUI

/// A record in the list, as the web's `RecordCard` draws it: `surface` fill, a 0.5 pt `border`, 12 pt radius, 12 pt
/// padding, slots 6 pt apart, and a faint drop shadow. Selected, the shadow gives way to a 2 pt inset `primary` ring;
/// the background and the border stay as they are.
///
/// Slots, top to bottom, each only when there is something to show: the parent chip (`showsParent`, for search
/// results), the title with its byline ("by <creator>  at <domain>") running on after it, the first image, the
/// summary or else the content as Markdown (4 lines), the meta row (type badge unless an artifact, the date, the
/// highlight count, `#tags`) and the note's bubble. An untitled record has no title line, so its content leads.
///
/// The card is presentation only: tapping, selection, swipe actions and context menus belong to the list.
public struct RecordCard: View {
    let record: ListRecord
    let isSelected: Bool
    let showsParent: Bool
    @Environment(\.serverURL) private var serverURL

    public init(_ record: ListRecord, isSelected: Bool = false, showsParent: Bool = false) {
        self.record = record
        self.isSelected = isSelected
        self.showsParent = showsParent
    }

    public var body: some View {
        let shape = Radius.shape(Radius.card)
        let parent = showsParent ? record.parent : nil
        VStack(alignment: .leading, spacing: Space.cardGap) {
            if let parent {
                ParentChip(parent: parent)
            }
            if let title = Self.titleLine(record, showsDomain: parent == nil, hasParent: parent != nil) {
                title
                    .wrapsFully()
            }
            if let media = record.media.first, media.isImage, let url = media.resolvedURL(server: serverURL) {
                CardImage(url: url, altText: media.altText)
            }
            if let summary = record.summary.nonBlank {
                Text(verbatim: summary)
                    .font(Typography.cardBody)
                    .lineSpacing(Typography.bodyLineSpacing)
                    .foregroundStyle(Palette.text)
                    .lineLimit(4)
                    .wrapsFully()
            } else if let content = record.content.nonBlank {
                MarkdownText(content, lineLimit: 4)
            }
            CardMetaRow(record: record)
            if let notes = record.notes.nonBlank {
                NoteBubble(notes)
                    .padding(.top, Metrics.noteTopMargin)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.cardPadding)
        .background {
            shape
                .fill(Palette.surface)
                .shadow(color: .black.opacity(isSelected ? 0 : 0.05), radius: 1, y: 1)
        }
        .overlay { shape.strokeBorder(Palette.border, lineWidth: Metrics.cardBorder) }
        .overlay {
            if isSelected {
                shape.strokeBorder(Palette.primary, lineWidth: Metrics.selectionRing)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The title, in `cardTitle` and `text`, with the byline set inline after it in `byline` and `textMuted`, so it
    /// runs on from the title's last line as the web's inline-flex heading does. Nil for an untitled record, unless
    /// the parent chip stands in for the title, as on the web.
    static func titleLine(_ record: ListRecord, showsDomain: Bool, hasParent: Bool) -> Text? {
        let title = record.title.nonBlank
        guard title != nil || hasParent else { return nil }
        let byline = byline(creator: record.creator?.title.nonBlank, domain: showsDomain ? record.domain : nil)
        switch (title, byline) {
        case (let title?, let byline?):
            return Text("\(titleText(title))  \(bylineText(byline))")
        case (let title?, nil):
            return titleText(title)
        case (nil, let byline?):
            return bylineText(byline)
        case (nil, nil):
            return nil
        }
    }

    /// "by Ann Leckie  at example.com", either half alone, or nil.
    static func byline(creator: String?, domain: String?) -> String? {
        let parts = [creator.map { "by \($0)" }, domain.map { DomainLabel.string($0) }].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }

    private static func titleText(_ title: String) -> Text {
        Text(verbatim: title)
            .font(Typography.cardTitle)
            .foregroundStyle(Palette.text)
    }

    private static func bylineText(_ byline: String) -> Text {
        Text(verbatim: byline)
            .font(Typography.byline)
            .foregroundStyle(Palette.textMuted)
    }
}

/// Type badge, Twitter mark, date, highlight count and tags, wrapping, in dimmed `meta` text.
private struct CardMetaRow: View {
    let record: ListRecord
    @ScaledMetric(relativeTo: .footnote) private var twitterIcon: CGFloat = 14

    var body: some View {
        FlowLayout(spacing: Space.metaGap, lineSpacing: Space.metaLineGap) {
            if record.type != .artifact {
                TypeBadge(record.type, size: .small)
            }
            if record.source == .twitter, let symbol = RecordSource.twitter.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: twitterIcon))
                    .accessibilityLabel("From Twitter")
            }
            if let date = record.recordCreatedAt.text(.card) {
                Text(verbatim: date)
            }
            if record.childCount > 0 {
                HighlightChip(count: record.childCount)
            }
            ForEach(RecordCard.tags(of: record), id: \.self) { tag in
                Text(verbatim: tag)
            }
        }
        .font(Typography.meta)
        .foregroundStyle(Palette.textDimmed)
    }
}

extension RecordCard {
    /// "#science-fiction" for each of the record's description targets (its `tagged_with` tags and `has_format`
    /// formats, as the web's card lists them), slugified like the web; duplicates once.
    static func tags(of record: ListRecord) -> [String] {
        var seen = Set<String>()
        return record.targets(ofType: .description).compactMap { target in
            let slug = Slug.make(target.title ?? target.slug)
            guard !slug.isEmpty, seen.insert(slug).inserted else { return nil }
            return "#\(slug)"
        }
    }
}

/// A card's first image: 150 pt tall, full width, 9 pt radius, cropped to fill with the point a quarter of the way
/// down kept in view (the web's `object-position: 50% 25%`), a hairline drawn over it, `elevated` while it loads.
private struct CardImage: View {
    let url: URL
    let altText: String?

    var body: some View {
        let shape = Radius.shape(Radius.image)
        Palette.elevated.view
            .frame(height: Metrics.cardImageHeight)
            .overlay(alignment: .top) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.clear
                }
                // Aligns the image's focus point with the frame's: a filled image taller than the frame is shifted
                // up by a quarter of the overflow; a wider one stays centered.
                .alignmentGuide(VerticalAlignment.top) { dimensions in
                    max(0, dimensions.height - Metrics.cardImageHeight) * Metrics.cardImageFocus.y
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
            .padding(.vertical, Space.iconGap)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: altText.nonBlank ?? ""))
            .accessibilityHidden(altText.nonBlank == nil)
    }
}

/// The record a search hit sits inside (a book for a highlight), above its title: elevated, 9 pt radius, 12 pt
/// medium muted text after a dimmed turn arrow.
private struct ParentChip: View {
    let parent: RecordRef
    @ScaledMetric(relativeTo: .caption) private var iconSize = Metrics.badgeIcon

    var body: some View {
        HStack(spacing: Space.iconGap) {
            Image(systemName: Symbol.parentChip)
                .font(.system(size: iconSize))
                .foregroundStyle(Palette.textDimmed)
                .accessibilityHidden(true)
            Text(verbatim: parent.title.nonBlank ?? parent.slug)
                .lineLimit(1)
        }
        .font(Typography.parentChip)
        .foregroundStyle(Palette.textMuted)
        .padding(Metrics.parentChipPadding)
        .background(Palette.elevated, in: Radius.shape(Radius.button))
        .accessibilityLabel(Text("In \(parent.title.nonBlank ?? parent.slug)"))
    }
}

extension Optional<String> {
    /// The string, unless it is nil or only whitespace.
    var nonBlank: String? {
        guard let self, !self.allSatisfy(\.isWhitespace) else { return nil }
        return self
    }
}

#if DEBUG
#Preview("Record cards") {
    ScrollView {
        LazyVStack(spacing: Space.cardGap) {
            MonthHeader("October 2026", count: PreviewSamples.listRecords.count)
                .padding(.bottom, Space.afterMonthHeader - Space.cardGap)
            ForEach(PreviewSamples.listRecords) { record in
                RecordCard(record, isSelected: record.id == PreviewSamples.listRecords[1].id)
            }
            RecordCard(PreviewSamples.listRecords[2], showsParent: true)
        }
        .padding(Space.margin)
    }
    .background(Palette.page)
    .previewRoot()
}
#endif
