import EnchiridionKit
import SwiftUI

extension EnvironmentValues {
    /// The server's origin, which media URLs (`/uploads/…`) are relative to. Set it once at the root
    /// (`.environment(\.serverURL, environment.serverURL)`); without it, only absolute media URLs load.
    @Entry public var serverURL: URL? = nil
}

extension Media {
    /// `url` resolved against `server` when there is one; otherwise `url` itself, if it is absolute.
    func resolvedURL(server: URL?) -> URL? {
        if let server { return url(relativeTo: server) }
        guard let absolute = URL(string: url), absolute.scheme != nil else { return nil }
        return absolute
    }
}
