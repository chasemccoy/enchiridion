import Foundation
import SwiftUI

/// A record's Markdown as the web's `MarkdownRender` shows it (markdown-it with `breaks: true` and `markdown-it-mark`):
/// a single newline is a line break, not a space; `==text==` is highlighted; bare URLs are links. Blocks are
/// paragraphs, headings, list items, quotes, fenced code and rules; raw HTML stays text, as the web's `html: false`
/// leaves it.
///
/// With a `lineLimit` (a card's 4-line clamp) the blocks are set as one `Text`, so the clamp counts lines across
/// them; without one, each block is its own view with the web's spacing, quote rule and code well.
public struct MarkdownText: View {
    /// `.compact` is the web's own size (13 pt body), for cards and short content; `.regular` sets the body one step
    /// up, for reading a record's content at length.
    public enum Size: Hashable, Sendable {
        case compact
        case regular
    }

    let source: String
    let size: Size
    let lineLimit: Int?

    public init(_ source: String, size: Size = .compact, lineLimit: Int? = nil) {
        self.source = source
        self.size = size
        self.lineLimit = lineLimit
    }

    public var body: some View {
        let blocks = MarkdownBlock.parse(source)
        Group {
            if let lineLimit {
                Text(MarkdownBlock.flattened(blocks))
                    .lineLimit(lineLimit)
                    .wrapsFully()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                        MarkdownBlockView(block: block, size: size)
                            .wrapsFully()
                            .padding(.top, index == 0 ? 0 : MarkdownBlock.gap(before: block, after: blocks[index - 1]))
                    }
                }
            }
        }
        .font(size.body)
        .lineSpacing(size.lineSpacing)
        .foregroundStyle(Palette.text)
        .tint(Palette.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MarkdownText.Size {
    var body: Font { self == .compact ? Typography.cardBody : Typography.readingBody }
    var lineSpacing: CGFloat { self == .compact ? Typography.bodyLineSpacing : Typography.readingLineSpacing }
    var code: Font { self == .compact ? Typography.code : Typography.readingCode }

    func heading(_ level: Int) -> Font {
        self == .compact ? Typography.heading(level) : Typography.readingHeading(level)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let size: MarkdownText.Size
    @ScaledMetric(relativeTo: .footnote) private var markerWidth = Metrics.listMarker
    @ScaledMetric(relativeTo: .footnote) private var indent = Metrics.listIndent

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(MarkdownBlock.inline(text))
        case .heading(let level, let text):
            Text(MarkdownBlock.inline(text))
                .font(size.heading(level))
                .accessibilityAddTraits(.isHeader)
        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: marker)
                    .foregroundStyle(Palette.textMuted)
                    .frame(width: markerWidth, alignment: .leading)
                Text(MarkdownBlock.inline(text))
            }
            .padding(.leading, CGFloat(depth) * indent)
        case .quote(let text):
            HStack(spacing: Metrics.quoteGap) {
                Palette.border.view
                    .frame(width: Metrics.quoteRule)
                Text(MarkdownBlock.inline(text))
                    .foregroundStyle(Palette.textMuted)
            }
            .wrapsFully()
        case .code(let code):
            Text(verbatim: code)
                .font(size.code)
                .lineSpacing(1)
                .padding(Metrics.codePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.elevated, in: Radius.shape(Radius.codeBlock))
        case .rule:
            Palette.borderMuted.view
                .frame(height: Metrics.rule)
                .padding(.vertical, Space.iconGap)
        }
    }
}

// MARK: Parsing

/// One block of a record's Markdown, holding its inline Markdown unparsed. The block grammar is the small part of
/// CommonMark that records use; inline syntax (emphasis, code, links, autolinks, escapes) is Foundation's.
enum MarkdownBlock: Hashable, Sendable {
    /// Lines joined by "\n", which stays a line break.
    case paragraph(String)
    case heading(level: Int, text: String)
    /// `marker` is "•" for `-`, `*` and `+`, or the item's own number ("3."). `depth` counts two-space indents.
    case listItem(marker: String, depth: Int, text: String)
    case quote(String)
    case code(String)
    case rule

    /// The space above `block` when it follows `previous`: list items sit closer together than other blocks.
    static func gap(before block: MarkdownBlock, after previous: MarkdownBlock) -> CGFloat {
        if case .listItem = block, case .listItem = previous { return Space.listItem }
        return Space.block
    }

    // MARK: Blocks

    private static let fencePattern = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})"#)
    private static let headingPattern =
        try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$"#)
    private static let rulePattern = try! NSRegularExpression(pattern: #"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let quotePattern = try! NSRegularExpression(pattern: #"^ {0,3}>[ \t]?(.*)$"#)
    private static let listItemPattern = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|\d{1,9}[.)])[ \t]+(.*)$"#)

    /// Splits `source` into blocks. Blank lines end a block; a line that starts another kind of block ends the
    /// current one; any other line continues it (a paragraph's, a list item's or, lazily, a quote's).
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var open: Open?
        var fenceMarker: String?
        var codeLines: [String] = []

        func close() {
            if let block = open?.block { blocks.append(block) }
            open = nil
        }

        for line in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init) {
            if let marker = fenceMarker {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    fenceMarker = nil
                    codeLines = []
                } else {
                    codeLines.append(line)
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                close()
            } else if let groups = match(fencePattern, line) {
                close()
                fenceMarker = groups[0]
            } else if let groups = match(headingPattern, line) {
                close()
                blocks.append(.heading(level: groups[0].count, text: groups[1]))
            } else if match(rulePattern, line) != nil {
                close()
                blocks.append(.rule)
            } else if let groups = match(quotePattern, line) {
                if case .quote(var lines)? = open {
                    lines.append(groups[0])
                    open = .quote(lines)
                } else {
                    close()
                    open = .quote([groups[0]])
                }
            } else if let groups = match(listItemPattern, line), !continuesParagraph(open, marker: groups[1]) {
                close()
                let marker = groups[1]
                let bullet = marker.count == 1 && "-*+".contains(marker) ? "•" : String(marker.dropLast()) + "."
                let indent = groups[0].reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                open = .listItem(marker: bullet, depth: min(indent / 2, 3), lines: [groups[2]])
            } else {
                switch open {
                case .paragraph(var lines)?:
                    lines.append(trimmed)
                    open = .paragraph(lines)
                case .listItem(let marker, let depth, var lines)?:
                    lines.append(trimmed)
                    open = .listItem(marker: marker, depth: depth, lines: lines)
                case .quote(var lines)?:
                    lines.append(trimmed)
                    open = .quote(lines)
                case nil:
                    open = .paragraph([trimmed])
                }
            }
        }
        // An unclosed fence runs to the end of the document, as in CommonMark.
        if fenceMarker != nil { blocks.append(.code(codeLines.joined(separator: "\n"))) }
        close()
        return blocks
    }

    /// A block still taking lines.
    private enum Open {
        case paragraph([String])
        case listItem(marker: String, depth: Int, lines: [String])
        case quote([String])

        var block: MarkdownBlock? {
            switch self {
            case .paragraph(let lines): .paragraph(lines.joined(separator: "\n"))
            case .listItem(let marker, let depth, let lines):
                .listItem(marker: marker, depth: depth, text: lines.joined(separator: "\n"))
            case .quote(let lines): .quote(lines.joined(separator: "\n"))
            }
        }
    }

    /// CommonMark's one exception to "a list item starts a block": an ordered item numbered other than 1 can't
    /// interrupt a paragraph, so "in\n1984. A year" stays one paragraph.
    private static func continuesParagraph(_ open: Open?, marker: String) -> Bool {
        guard case .paragraph? = open, let number = Int(marker.dropLast()) else { return false }
        return number != 1
    }

    /// The capture groups of `regex` matched against the whole of `line` (an unmatched optional group is "").
    private static func match(_ regex: NSRegularExpression, _ line: String) -> [String]? {
        let range = NSRange(line.startIndex..., in: line)
        guard let result = regex.firstMatch(in: line, range: range) else { return nil }
        return (1 ..< result.numberOfRanges).map { index in
            Range(result.range(at: index), in: line).map { String(line[$0]) } ?? ""
        }
    }

    // MARK: Inline

    private static let inlineOptions = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: false,
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )
    /// markdown-it-mark's `==text==`: no space just inside either delimiter, and not across lines.
    private static let markPattern = try! NSRegularExpression(pattern: #"==(?=\S)([^\n]*?\S)=="#)

    /// Inline Markdown as attributed text: Foundation's parser, with whitespace (and so every newline) kept, which
    /// also links bare URLs; then `==marks==` highlighted, and links underlined as the web draws them. SwiftUI's
    /// `Text` sets links in the tint and emphasis and code from their presentation intents.
    static func inline(_ markdown: String) -> AttributedString {
        var text = (try? AttributedString(markdown: markdown, options: inlineOptions)) ?? AttributedString(markdown)
        highlightMarks(in: &text)
        for range in text.runs.filter({ $0.link != nil }).map(\.range) {
            text[range][AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = .single
        }
        return text
    }

    /// Replaces each `==text==` outside code with `text` in the mark colors. Matches are handled last to first, so
    /// each removal leaves the offsets of the ones still to come unchanged; ranges are rebuilt from offsets after
    /// every removal because removing characters invalidates `AttributedString` indices.
    private static func highlightMarks(in text: inout AttributedString) {
        let plain = String(text.characters)
        guard plain.contains("==") else { return }
        let matches = markPattern.matches(in: plain, range: NSRange(plain.startIndex..., in: plain))
        for match in matches.reversed() {
            let inner = match.range(at: 1)
            guard let innerRange = Range(inner, in: text),
                  !text[innerRange].runs.contains(where: { $0.inlinePresentationIntent?.contains(.code) == true })
            else { continue }
            text[innerRange][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] =
                Palette.markBackground.color
            text[innerRange][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Palette.markText.color
            if let closing = Range(NSRange(location: NSMaxRange(inner), length: 2), in: text) {
                text.removeSubrange(closing)
            }
            if let opening = Range(NSRange(location: match.range.location, length: 2), in: text) {
                text.removeSubrange(opening)
            }
        }
    }

    // MARK: Flattening

    /// All of `blocks` as one attributed string, a block per line, for a clamped `Text`: headings bold, list items
    /// after their marker, quotes muted, code monospaced, rules dropped.
    static func flattened(_ blocks: [MarkdownBlock]) -> AttributedString {
        var result = AttributedString()
        for block in blocks {
            var line: AttributedString
            switch block {
            case .paragraph(let text):
                line = inline(text)
            case .heading(_, let text):
                line = inline(text)
                for run in line.runs {
                    line[run.range].inlinePresentationIntent =
                        (run.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
                }
            case .listItem(let marker, _, let text):
                line = AttributedString("\(marker) ")
                line.append(inline(text))
            case .quote(let text):
                line = inline(text)
                line[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Palette.textMuted.color
            case .code(let code):
                line = AttributedString(code)
                line.inlinePresentationIntent = .code
            case .rule:
                continue
            }
            if !result.characters.isEmpty { result.append(AttributedString("\n")) }
            result.append(line)
        }
        return result
    }
}

#if DEBUG
#Preview("Markdown") {
    ScrollView {
        VStack(alignment: .leading, spacing: Space.monthGap) {
            MarkdownText(PreviewSamples.markdown)
            MarkdownText(PreviewSamples.markdown, size: .regular)
            MarkdownText(PreviewSamples.markdown, lineLimit: 4)
        }
        .padding(Space.margin)
    }
    .previewRoot()
}
#endif
