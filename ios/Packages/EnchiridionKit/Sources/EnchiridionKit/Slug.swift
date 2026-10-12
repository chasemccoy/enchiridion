import Foundation

/// Record slugs. The server requires a non-empty, unique slug on every `PUT /record` and never makes one, so the client
/// does, the way the web does.
public enum Slug {
    /// A port of the web's `slugify(str, {lower: true, strict: true, trim: true})` (slugify 1.6.9, default charMap;
    /// the `en` locale it passes has no table of its own):
    ///
    /// 1. NFC-normalize.
    /// 2. Replace each character from the charMap ("é" → "e", "&" → "and", "ß" → "ss", "’" → "'"); a resulting "-"
    ///    becomes a space, so existing hyphens separate words.
    /// 3. Strict mode: keep only ASCII letters, digits and whitespace.
    /// 4. Trim, turn each run of whitespace into "-", lowercase.
    ///
    /// A title with nothing left (emoji, CJK) yields "": callers fall back to `fallback()`.
    public static func make(_ title: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in title.precomposedStringWithCanonicalMapping.unicodeScalars {
            let mapped = charMap[scalar].map { $0 == "-" ? " " : $0 } ?? (scalar == "-" ? " " : String(scalar))
            for character in mapped.unicodeScalars where isASCIIAlphanumeric(character) || isJSWhitespace(character) {
                kept.append(character)
            }
        }
        var slug = ""
        var pendingSeparator = false
        for scalar in kept {
            if isJSWhitespace(scalar) {
                pendingSeparator = !slug.isEmpty
            } else {
                if pendingSeparator { slug.append("-") }
                pendingSeparator = false
                slug.unicodeScalars.append(scalar)
            }
        }
        return slug.lowercased()
    }

    /// A slug for a record with nothing to make one from: `note-` and 8 lowercase hex digits, like the live
    /// database's untitled notes (`note-e5f4405b`).
    public static func fallback() -> String {
        var generator = SystemRandomNumberGenerator()
        return fallback(using: &generator)
    }

    public static func fallback(using generator: inout some RandomNumberGenerator) -> String {
        let hex = String(UInt32.random(in: .min ... .max, using: &generator), radix: 16)
        return "note-" + String(repeating: "0", count: 8 - hex.count) + hex
    }

    private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A: true
        default: false
        }
    }

    /// JavaScript's `\s`, which is also exactly what `String.prototype.trim` removes.
    private static func isJSWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09 ... 0x0D, 0x20, 0xA0, 0x1680, 0x2000 ... 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }
}
