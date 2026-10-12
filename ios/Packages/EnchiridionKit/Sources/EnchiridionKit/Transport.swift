import Foundation

/// The one network seam. `URLSessionTransport` is live; tests answer from stubs.
public protocol HTTPTransport: Sendable {
    /// Sends `request` and returns the whole body. Transport failures surface as whatever the transport throws
    /// (URLError for the live one); `EnchiridionClient` maps them.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Sends requests with a URLSession.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .enchiridion) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

extension URLSession {
    /// Ephemeral: no URLCache and no cookies, and `waitsForConnectivity = false` so a request fails at once (and
    /// "Tailscale is off" shows) instead of waiting for a network that may never come.
    public static let enchiridion: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}

extension URLCache {
    /// How much media `URLCache.shared` holds in memory once `keepMediaInMemory()` has run: enough for a library's
    /// images to revalidate cheaply (`/uploads` is served `max-age=0`, with an ETag) while the app runs.
    public static let mediaMemoryCapacity = 32 * 1024 * 1024

    /// Makes the shared cache memory-only, and empties what an earlier build left on disk. SwiftUI's `AsyncImage`
    /// loads record images through `URLSession.shared`, whose default cache keeps responses under a few hundred KB on
    /// disk; the app stores nothing from the server on the device, so the app and the share extension call this at
    /// launch, before anything loads.
    public static func keepMediaInMemory() {
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared = URLCache(memoryCapacity: mediaMemoryCapacity, diskCapacity: 0)
    }
}
