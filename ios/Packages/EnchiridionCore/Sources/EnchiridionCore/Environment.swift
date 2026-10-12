import EnchiridionKit
import Foundation

/// Every wait the models make, in one place, so tests and previews can shrink them.
public struct Timings: Hashable, Sendable {
    /// Typing in the search field waits this long for the next keystroke before asking the server.
    public var searchDebounce: Duration
    /// How long the share card shows "Saved to Enchiridion" before it closes. The model doesn't wait on it; the share
    /// view does.
    public var savedLinger: Duration
    /// The most one share save may take, all its requests together (slug lookups, the create, the check after a lost
    /// answer). Each request's own timeout is an idle timeout, so without this a stalled server could hold the card on
    /// "Saving…" for several of them. Past it the save fails as unreachable, and Retry checks the slug first.
    public var shareDeadline: Duration
    /// The same for one save in the record editor, whose sheet can't be cancelled or swiped away while it saves. As
    /// long as one app request's timeout, so a stalled request ends the save about when it would have anyway, and a
    /// run of them (a probe, the create, the check after a lost answer) can't stack up.
    public var editorDeadline: Duration

    public init(searchDebounce: Duration = .milliseconds(250), savedLinger: Duration = .seconds(1),
                shareDeadline: Duration = .seconds(10), editorDeadline: Duration = .seconds(30)) {
        self.searchDebounce = searchDebounce
        self.savedLinger = savedLinger
        self.shareDeadline = shareDeadline
        self.editorDeadline = editorDeadline
    }

    public static let standard = Timings()

    /// No debounce or linger: tests and previews. The deadlines stay, since a zero one would always win.
    public static let immediate = Timings(searchDebounce: .zero, savedLinger: .zero)
}

/// Everything a model touches outside itself, so tests swap each piece: the server, the network, time and the
/// randomness in fallback slugs. Models build their own clients from it with `client(role:)`.
public struct AppEnvironment: Sendable {
    /// The API's origin: `Server.production`, or a DEBUG build's `-EnchiridionServer`.
    public var server: URL
    public var transport: any HTTPTransport
    /// `CFBundleShortVersionString`, for `X-Enchiridion-Client`.
    public var appVersion: String
    public var platform: String
    public var now: @Sendable () -> Date
    /// What debounces sleep on. Tests pass a manual clock.
    public var clock: any Clock<Duration>
    /// The zone month headers are cut in. `autoupdatingCurrent` follows the device as it travels.
    public var timeZone: TimeZone
    public var timings: Timings
    /// The slug for a record with no title or URL to make one from (`Slug.fallback()`); tests make it predictable.
    public var fallbackSlug: @Sendable () -> String

    public init(server: URL = Server.production, transport: any HTTPTransport = URLSessionTransport(),
                appVersion: String, platform: String = "ios", now: @escaping @Sendable () -> Date = { Date() },
                clock: any Clock<Duration> = ContinuousClock(), timeZone: TimeZone = .autoupdatingCurrent,
                timings: Timings = .standard, fallbackSlug: @escaping @Sendable () -> String = { Slug.fallback() }) {
        self.server = server
        self.transport = transport
        self.appVersion = appVersion
        self.platform = platform
        self.now = now
        self.clock = clock
        self.timeZone = timeZone
        self.timings = timings
        self.fallbackSlug = fallbackSlug
    }

    /// The app's: URLSession and the given server (the app passes `Server.fromArguments` in DEBUG builds).
    public static func live(server: URL = Server.production, bundle: Bundle = .main) -> AppEnvironment {
        AppEnvironment(server: server, appVersion: appVersion(of: bundle))
    }

    /// The share extension's: the production server unless a DEBUG build passes the one its Info.plist names
    /// (`Server.fromInfoDictionary`), since an extension gets no launch arguments.
    public static func shareExtension(server: URL = Server.production, bundle: Bundle = .main) -> AppEnvironment {
        AppEnvironment(server: server, appVersion: appVersion(of: bundle))
    }

    /// The bundle's `CFBundleShortVersionString`, "0" when it has none (or XcodeGen left the build setting unexpanded).
    public static func appVersion(of bundle: Bundle) -> String {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty, !version.contains("$(")
        else { return "0" }
        return version
    }

    /// A client for `role`: the app's (30 s timeout) or the share extension's (10 s).
    public func client(role: ClientRole = .app) -> EnchiridionClient {
        EnchiridionClient(.init(server: server, role: role, appVersion: appVersion, platform: platform),
                          transport: transport)
    }

    /// Sleeps on `clock`; a zero or negative duration returns at once. Throws `CancellationError` when cancelled.
    func sleep(for duration: Duration) async throws {
        guard duration > .zero else { return try Task.checkCancellation() }
        try await clock.sleep(for: duration)
    }
}
