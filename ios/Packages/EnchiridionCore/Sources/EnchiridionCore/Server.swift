import Foundation

/// Where Enchiridion's API is.
///
/// The address is a constant: voyager recognizes the device through Tailscale, so there is nothing to sign in with and
/// nothing about the server is ever stored. A DEBUG build may point elsewhere: the app with `-EnchiridionServer
/// <origin>` (`fromArguments`), and both the app and the share extension (which never sees launch arguments) with the
/// `EnchiridionServer` Info.plist key, which `ENCHIRIDION_SERVER` in the gitignored `Config/Local.xcconfig` fills
/// (`fromInfoDictionary`). Release builds always use `production`. An override that is set but isn't an http(s) origin
/// never falls back to production: it gives `misconfigured`, where every request fails, so a build meant for a sandbox
/// can't write to the live database.
public enum Server {
    /// Caddy on voyager, reachable only through the tailnet.
    public static let production = URL(string: "https://enchiridion-api.chsmc.tools")!

    /// The launch argument a DEBUG build reads: `-EnchiridionServer http://localhost:4321`.
    public static let argument = "-EnchiridionServer"

    /// The Info.plist key a DEBUG build reads, set from the `ENCHIRIDION_SERVER` build setting (empty by default).
    public static let infoKey = "EnchiridionServer"

    /// Where a DEBUG build goes when its override names no usable server: a reserved name that never resolves (RFC
    /// 6761), so every request fails, and Settings' Server row says why.
    public static let misconfigured = URL(string: "https://enchiridion-server-misconfigured.invalid")!

    /// The origin after `-EnchiridionServer`; `fallback` without the argument; `misconfigured` when it is there with
    /// no value or one that isn't an http(s) address.
    public static func fromArguments(_ arguments: [String], fallback: URL = production) -> URL {
        guard let index = arguments.firstIndex(of: argument) else { return fallback }
        guard arguments.indices.contains(index + 1) else { return misconfigured }
        return overridden(arguments[index + 1])
    }

    /// The origin in the bundle's `EnchiridionServer` key; nil when it is unset (missing, empty or unexpanded), and
    /// `misconfigured` when it is set to anything that isn't an http(s) address.
    public static func fromInfoDictionary(_ bundle: Bundle) -> URL? {
        fromInfoValue(bundle.object(forInfoDictionaryKey: infoKey))
    }

    static func fromInfoValue(_ value: Any?) -> URL? {
        guard let value else { return nil }
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces) else { return misconfigured }
        if text.isEmpty || text.contains("$(") { return nil }
        return overridden(text)
    }

    /// The server an override names, or `misconfigured`: an override was asked for, so never production.
    static func overridden(_ text: String) -> URL {
        // "http:" is what xcconfig leaves of `http://…` (its `//` starts a comment); `origin` would read it as the
        // host "http".
        if text.trimmingCharacters(in: .whitespaces).hasSuffix(":") { return misconfigured }
        return origin(text) ?? misconfigured
    }

    /// The origin of a typed address: scheme, host and port, "https://" assumed, any path, query or fragment dropped
    /// (the client appends paths to it). nil when the text isn't an http(s) address.
    public static func origin(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host
        origin.port = components.port
        return origin.url
    }

    /// "enchiridion-api.chsmc.tools", or "localhost:4321" when the origin names a port: Settings' Server row.
    public static func displayHost(_ server: URL) -> String {
        guard let host = server.host(), !host.isEmpty else { return server.absoluteString }
        return server.port.map { "\(host):\($0)" } ?? host
    }
}
