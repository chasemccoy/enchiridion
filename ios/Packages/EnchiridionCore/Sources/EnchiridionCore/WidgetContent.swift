import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What the widget needs from a record's content and media, without a view: a plain-text excerpt and a small image.
public enum WidgetContent {
    /// The content as plain text for a few lines: Markdown's block markers (headings, quotes, list bullets) and inline
    /// marks (emphasis, code, links, keeping their text) dropped, blank lines between paragraphs kept as one line
    /// break, cut to `limit` characters at a word. Nil when nothing is left.
    public static func excerpt(_ markdown: String?, limit: Int = 600) -> String? {
        guard let markdown else { return nil }
        var lines: [String] = []
        for raw in markdown.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.allSatisfy({ "-*_=".contains($0) }) { continue }
            line = line.replacing(/^(#{1,6}|>+|[-*+]|\d+[.)])\s+/, with: "")
            if let parsed = try? AttributedString(
                markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                line = String(parsed.characters)
            }
            line = line.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { lines.append(line) }
        }
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        let atWord = cut.lastIndex(where: \.isWhitespace).map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }

    /// The image downsampled so its longer side is at most `maxPixelSize`, as JPEG: a widget's process gets a few
    /// tens of megabytes, so it never holds a full-size photo. Nil for data ImageIO can't read (SVG, a PDF).
    public static func thumbnail(_ data: Data, maxPixelSize: Int) -> Data? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
