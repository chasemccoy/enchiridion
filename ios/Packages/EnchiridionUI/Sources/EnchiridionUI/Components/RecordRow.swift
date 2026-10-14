import EnchiridionCore
import EnchiridionKit
import SwiftUI

/// A record in the list as a plain iOS row: edge to edge, the list's hairlines between rows, and inside it the web
/// card's slots, 6 pt apart, each only when there is something to show. Top to bottom: the record a search hit sits
/// in (a book for a highlight), the title (semibold, two lines), the first image (150 pt, full width), the summary or
/// else the content as plain text (three lines), a muted line of who or where, when, the type unless an artifact, the
/// highlight count and `#tags`, and the note's bubble. An untitled record leads with its content.
///
/// The row is presentation only: tapping, selection, swipe actions and context menus belong to the list.
public struct RecordRow: View {
    let record: ListRecord
    let showsParent: Bool
    @Environment(\.serverURL) private var serverURL

    public init(_ record: ListRecord, showsParent: Bool = false) {
        self.record = record
        self.showsParent = showsParent
    }

    public var body: some View {
        let title = record.title.nonBlank
        let excerpt = WidgetContent.excerpt(record.content, limit: 400)
        VStack(alignment: .leading, spacing: Space.cardGap) {
            if showsParent, let parent = record.parent {
                // A Label's system gap is wide at this size: the arrow sits as close as a badge's icon does.
                HStack(spacing: Space.iconGap) {
                    Image(systemName: Symbol.parentChip)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(verbatim: parent.title.nonBlank ?? parent.slug)
                }
                .font(Typography.rowMeta)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
                .accessibilityLabel(Text("In \(parent.title.nonBlank ?? parent.slug)"))
            }
            if let title {
                Text(verbatim: title)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.textHighlighted)
                    .lineLimit(2)
            }
            if let media = record.media.first(where: \.isImage), let url = media.resolvedURL(server: serverURL) {
                RowImage(url: url, altText: media.altText)
            }
            if let text = record.summary.nonBlank ?? (title == nil ? nil : excerpt) {
                Text(verbatim: Self.oneParagraph(text))
                    .font(Typography.rowBody)
                    .lineSpacing(Typography.bodyLineSpacing)
                    .foregroundStyle(Palette.text)
                    .lineLimit(3)
            } else if title == nil, let excerpt {
                Text(verbatim: Self.oneParagraph(excerpt))
                    .font(Typography.rowLead)
                    .lineSpacing(Typography.bodyLineSpacing)
                    .foregroundStyle(Palette.textHighlighted)
                    .lineLimit(4)
            }
            if let meta = Self.meta(record) {
                Text(verbatim: meta)
                    .font(Typography.rowMeta)
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(2)
            }
            if let notes = record.notes.nonBlank {
                NoteBubble(notes)
                    .padding(.top, Space.iconGap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }

    /// Paragraphs run together rather than break after the first.
    static func oneParagraph(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// "Robin Sloan · Oct 7 · Concept · 3 highlights · #essays #web", each part only when there is one: the creator
    /// else the domain, the date, the type unless an artifact, the highlight count, the tags.
    static func meta(_ record: ListRecord) -> String? {
        var parts: [String] = []
        if let who = record.creator?.title.nonBlank ?? record.domain { parts.append(who) }
        if let date = record.recordCreatedAt.text(.card) { parts.append(date) }
        if record.type != .artifact { parts.append(record.type.displayName) }
        if record.childCount > 0 {
            parts.append(record.childCount == 1 ? "1 highlight" : "\(record.childCount) highlights")
        }
        let tags = tags(of: record)
        if !tags.isEmpty { parts.append(tags.joined(separator: " ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

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

/// A row's first image: 150 pt tall, full width, 9 pt radius, cropped to fill with the point a quarter of the way
/// down kept in view (the web's `object-position: 50% 25%`), a hairline drawn over it, `elevated` while it loads.
private struct RowImage: View {
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
            .overlay { shape.strokeBorder(Palette.border, lineWidth: Metrics.cardBorder) }
            .padding(.vertical, Space.iconGap / 2)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: altText.nonBlank ?? ""))
            .accessibilityHidden(altText.nonBlank == nil)
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
#Preview("Record rows") {
    List {
        ForEach(PreviewSamples.listRecords) { record in
            RecordRow(record)
        }
        RecordRow(PreviewSamples.listRecords[2], showsParent: true)
    }
    .listStyle(.plain)
    .previewRoot()
}
#endif
