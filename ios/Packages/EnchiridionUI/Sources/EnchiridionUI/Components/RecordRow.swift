import EnchiridionCore
import EnchiridionKit
import SwiftUI

/// A record in the list as a plain iOS row, as Mail and Reader draw theirs: the title (semibold, two lines), the
/// summary or else the content as plain text (two lines), and a muted line of who or where, when, and the rest (type
/// unless an artifact, highlights, the note), with the first image as a thumbnail at the trailing edge. A search hit
/// inside another record (a highlight in a book) says so above its title. An untitled record leads with its content.
///
/// Edge to edge on the page, separated by the list's own hairlines; the list draws selection and the pressed state.
/// The row is presentation only: tapping, swipe actions and context menus belong to the list.
public struct RecordRow: View {
    let record: ListRecord
    let showsParent: Bool
    @Environment(\.serverURL) private var serverURL
    @ScaledMetric(relativeTo: .body) private var thumbnailSize = Metrics.rowThumbnail

    public init(_ record: ListRecord, showsParent: Bool = false) {
        self.record = record
        self.showsParent = showsParent
    }

    public var body: some View {
        let title = record.title.nonBlank
        let excerpt = WidgetContent.excerpt(record.content, limit: 280)
        HStack(alignment: .top, spacing: Space.cardPadding) {
            VStack(alignment: .leading, spacing: Space.metaLineGap) {
                if showsParent, let parent = record.parent {
                    Label {
                        Text(verbatim: parent.title.nonBlank ?? parent.slug)
                    } icon: {
                        Image(systemName: Symbol.parentChip)
                    }
                    .font(Typography.byline)
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
                if let text = record.summary.nonBlank ?? (title == nil ? nil : excerpt) {
                    Text(verbatim: Self.oneParagraph(text))
                        .font(Typography.cardBody)
                        .lineSpacing(Typography.bodyLineSpacing)
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                } else if title == nil, let excerpt {
                    Text(verbatim: Self.oneParagraph(excerpt))
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textHighlighted)
                        .lineLimit(3)
                }
                if let meta = Self.meta(record) {
                    Text(verbatim: meta)
                        .font(Typography.byline)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let media = record.media.first(where: \.isImage), let url = media.resolvedURL(server: serverURL) {
                RowThumbnail(url: url, size: thumbnailSize)
            }
        }
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }

    /// Paragraphs run together on two lines rather than break after the first.
    static func oneParagraph(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// "Robin Sloan · Oct 7 · Concept · 3 highlights · Read again", each part only when there is one: the creator
    /// else the domain, the date, the type unless an artifact, the highlight count, the note's first line.
    static func meta(_ record: ListRecord) -> String? {
        var parts: [String] = []
        if let who = record.creator?.title.nonBlank ?? record.domain { parts.append(who) }
        if let date = record.recordCreatedAt.text(.card) { parts.append(date) }
        if record.type != .artifact { parts.append(record.type.displayName) }
        if record.childCount > 0 {
            parts.append(record.childCount == 1 ? "1 highlight" : "\(record.childCount) highlights")
        }
        if let note = record.notes.nonBlank?.split(whereSeparator: \.isNewline).first {
            parts.append(String(note).trimmingCharacters(in: .whitespaces))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The first image, square, cropped to fill, `elevated` while it loads, a hairline over it.
private struct RowThumbnail: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        let shape = Radius.shape(Radius.image)
        Palette.elevated.view
            .frame(width: size, height: size)
            .overlay {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Palette.border, lineWidth: Metrics.cardBorder) }
            .accessibilityHidden(true)
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
