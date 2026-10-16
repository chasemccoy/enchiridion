import CoreText
import Foundation
import os
import Synchronization

/// Martina Plantijn, the web app's serif, registered for this process at launch from the `.woff2` files the app and
/// the share extension bundle (`app/public/fonts/martina-plantijn/regular.woff2` and `medium.woff2`, copied to the
/// bundle's root by `project.yml`).
///
/// Registered at runtime rather than through `UIAppFonts`, which documents only TrueType and OpenType: CoreText reads
/// WOFF2 when it is handed the file directly. `CTFontManagerRegisterFontsForURL` is used because it is synchronous
/// and reports per-file errors; descriptors made by `CTFontManagerCreateFontDescriptorsFromData` can't be registered
/// (`CTFontManagerRegisterFontDescriptors` refuses them with "insufficient info", 303), and SwiftUI's `Font.custom`
/// finds a face only by a registered name.
///
/// Until (or unless) registration succeeds, `Typography.serif` falls back to the system serif, New York, which is
/// also in the web's own `--font-serif` stack.
public enum FontRegistry {
    /// The two faces the web declares (`@font-face` 400 and 500), by PostScript name. The family name inside
    /// `regular.woff2` is mangled ("Copyright Klim Type Foundry"), so faces are only ever looked up by these.
    public enum Face: String, CaseIterable, Hashable, Sendable {
        case regular = "MartinaPlantijn-Regular"
        case medium = "MartinaPlantijn-Medium"

        public var postScriptName: String { rawValue }

        /// The file's name without its extension, as the web's `public/fonts/martina-plantijn/` names it.
        public var fileName: String {
            switch self {
            case .regular: "regular"
            case .medium: "medium"
            }
        }
    }

    /// Registers both faces from `bundle`'s root. Safe to call more than once and from any thread; a face that is
    /// already registered counts as registered. Returns whether every face is now available.
    @discardableResult
    public static func register(bundle: Bundle = .main) -> Bool {
        register { face in bundle.url(forResource: face.fileName, withExtension: "woff2") }
    }

    /// Registers both faces from a folder holding `regular.woff2` and `medium.woff2` (previews and scripts, which
    /// read the web app's copy instead of a bundle's).
    @discardableResult
    public static func register(directory: URL) -> Bool {
        register { face in
            let url = directory.appending(path: "\(face.fileName).woff2")
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
        }
    }

    /// Whether every face is registered and resolvable by its PostScript name.
    public static var isRegistered: Bool {
        available.withLock { $0.count == Face.allCases.count }
    }

    /// Whether `face` is registered and resolvable by its PostScript name.
    public static func isAvailable(_ face: Face) -> Bool {
        available.withLock { $0.contains(face) }
    }

    // MARK: Registration

    private static let available = Mutex<Set<Face>>([])
    private static let log = Logger(subsystem: "com.chsmc.enchiridion", category: "fonts")

    /// `kCTFontManagerErrorAlreadyRegistered`: this process registered the file before (from another bundle or
    /// folder holding the same font), which is as good as registering it now.
    private static let alreadyRegistered = 105

    private static func register(locate: (Face) -> URL?) -> Bool {
        available.withLock { available in
            let missing = Face.allCases.filter { !available.contains($0) }
            for face in missing {
                guard let url = locate(face) else {
                    log.error("Martina Plantijn: \(face.fileName, privacy: .public).woff2 isn't bundled")
                    continue
                }
                var error: Unmanaged<CFError>?
                if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                    let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
                    if code != alreadyRegistered {
                        log.error(
                            "Martina Plantijn: \(face.fileName, privacy: .public).woff2 didn't register (\(code))")
                        continue
                    }
                }
                // Trust a name lookup, not the call's result: a font that registered under some other name would
                // leave `Font.custom` silently drawing the system sans.
                if resolves(face) {
                    available.insert(face)
                } else {
                    log.error("Martina Plantijn: \(face.postScriptName, privacy: .public) doesn't resolve by name")
                }
            }
            #if DEBUG
            // Notice level, not debug or info, so a plain `log show` (which drops those levels) proves the serif
            // registered: in the Simulator, `xcrun simctl spawn booted log show --predicate 'subsystem ==
            // "com.chsmc.enchiridion"'` (the Mac's own log never sees it); on a device, Console.app. Logged once:
            // only when this call added a face.
            let added = missing.filter { available.contains($0) }.map(\.postScriptName)
            if !added.isEmpty {
                log.notice("Martina Plantijn registered: \(added.joined(separator: ", "), privacy: .public)")
            }
            #endif
            return available.count == Face.allCases.count
        }
    }

    /// CoreText substitutes a default face for an unknown name, so a lookup is only a hit when the name round-trips.
    private static func resolves(_ face: Face) -> Bool {
        let font = CTFontCreateWithName(face.postScriptName as CFString, 12, nil)
        return CTFontCopyPostScriptName(font) as String == face.postScriptName
    }
}
