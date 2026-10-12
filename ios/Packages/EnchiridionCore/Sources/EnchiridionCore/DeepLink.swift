import Foundation

/// The app's own links, `enchiridion://record/<id>`: how a Shortcut (or anything else on the phone) opens a record.
public enum DeepLink {
    public static let scheme = "enchiridion"

    /// The link that opens record `id`.
    public static func record(_ id: Int) -> URL {
        URL(string: "\(scheme)://record/\(id)")!
    }

    /// The record a link opens; nil for anything else.
    public static func recordID(from url: URL) -> Int? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "record" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let id = Int(parts[0]), id > 0 else { return nil }
        return id
    }
}
