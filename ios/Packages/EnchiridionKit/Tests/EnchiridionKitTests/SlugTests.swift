@testable import EnchiridionKit
import Foundation
import Testing

@Suite struct SlugTests {
    /// The web's tests (`tests/formatting.test.ts`) first; the rest are slugify 1.6.9's output for the same input, run
    /// with the web's options.
    @Test(arguments: [
        ("Hello, World!", "hello-world"),
        ("What's New?", "whats-new"),
        ("  padded  title  ", "padded-title"),
        ("already-a-slug", "already-a-slug"),
        ("😀🎉", ""),
        ("Crème brûlée & café", "creme-brulee-and-cafe"),
        ("50% off <b>|</b>", "50percent-off-lessbgreaterorlessbgreater"),
        ("Straße", "strasse"),
        ("“Quoted” — dash – en", "quoted-dash-en"),
        ("C++ in 2026", "c-in-2026"),
        ("foo\u{00A0}bar", "foo-bar"),
        ("tab\tsep\nline", "tab-sep-line"),
        ("naïve résumé", "naive-resume"),
        ("Ærøskøbing", "aeroskobing"),
        ("under_score", "underscore"),
        ("a/b/c", "abc"),
        ("e\u{0301} (decomposed)", "e-decomposed"),
        ("100$ €5", "100dollar-euro5"),
        ("Привет мир", "privet-mir"),
        ("日本語のタイトル", ""),
        ("x — y", "x-y"),
        ("...", ""),
        ("A.B.C", "abc"),
        ("\u{2028}sep\u{3000}wide", "sep-wide"),
        ("İstanbul", "istanbul"),
        ("It’s “fine”", "its-fine"),
        ("", ""),
    ])
    func make(title: String, slug: String) {
        #expect(Slug.make(title) == slug)
    }

    @Test func fallbackShape() {
        let slug = Slug.fallback()
        #expect(slug.count == 13)
        #expect(slug.hasPrefix("note-"))
        #expect(slug.dropFirst(5).allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(Slug.make(slug) == slug)                 // already a valid slug
    }

    @Test func fallbackPadsToEightDigits() {
        var zero = FixedGenerator(value: 0)
        #expect(Slug.fallback(using: &zero) == "note-00000000")
        var max = FixedGenerator(value: .max)
        #expect(Slug.fallback(using: &max) == "note-ffffffff")
    }
}

/// Returns the same value forever.
private struct FixedGenerator: RandomNumberGenerator {
    var value: UInt64
    mutating func next() -> UInt64 { value }
}
