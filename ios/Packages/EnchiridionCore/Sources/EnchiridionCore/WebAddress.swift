import Foundation

/// A record's `url` as a web address. People type bare hosts (`example.com/page`, the editor's own prompt), so a text
/// without a scheme is read as https, as the web's links do through the browser.
public enum WebAddress {
    /// An http(s) address as stored, or a bare `example.com/page` with https assumed; nil for anything else (text with
    /// spaces, `mailto:`, no host).
    public static func url(_ text: String?) -> URL? {
        guard let candidate = withScheme(text),
              let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    /// The text trimmed, with `https://` in front when it has no scheme; nil when it is blank or holds whitespace.
    static func withScheme(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              !trimmed.contains(where: \.isWhitespace)
        else { return nil }
        return hasScheme(trimmed) ? trimmed : "https://" + trimmed
    }

    /// Whether the text starts with a scheme (`https:`, `mailto:`), as opposed to a bare host, which may carry a port
    /// (`localhost:4321/x`).
    static func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+.-".contains($0)) })
        else { return false }
        return !(text[text.index(after: colon)...].first?.isNumber ?? false)
    }
}
