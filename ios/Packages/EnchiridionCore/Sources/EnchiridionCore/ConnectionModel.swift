import EnchiridionKit
import Foundation
import Observation

/// Settings › Connection: how voyager knows this device, from `GET /me`.
@MainActor @Observable
public final class ConnectionModel {
    public let server: URL

    /// The last answer from `/me`. Cleared by a 401, kept through other failures (the device is still the device).
    public private(set) var me: Me?
    /// The last check's failure; nil once one succeeds.
    public private(set) var lastError: EnchiridionError?
    public private(set) var isChecking = false
    /// When `/me` last answered.
    public private(set) var checkedAt: Date?

    @ObservationIgnored private let client: EnchiridionClient
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(environment: AppEnvironment) {
        server = environment.server
        now = environment.now
        client = environment.client(role: .app)
    }

    /// "enchiridion-api.chsmc.tools".
    public var host: String { Server.displayHost(server) }

    /// The status line: the last failure if the last check failed, else how the device is signed in, "Checking…"
    /// before the first answer; nil before any check.
    public var status: String? {
        StatusText.connection(me: me, error: lastError, checking: isChecking)
    }

    /// This device as Tailscale names it: from `/me`, or from a 401 that named it.
    public var device: Device? {
        if let device = me?.device { return device }
        if case .unauthorized(let device) = lastError { return device }
        return nil
    }

    /// The last check was a 401: the not-allowed state.
    public var isNotAllowed: Bool {
        if case .unauthorized = lastError { return true }
        return false
    }

    /// Asks `/me` again. Settings calls it on appear; a check already in flight is not doubled.
    public func refresh() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            me = try await client.me()
            lastError = nil
            checkedAt = now()
        } catch {
            guard let error = EnchiridionError.classify(error) else { return }
            if case .unauthorized = error { me = nil }
            lastError = error
        }
    }
}

/// Settings' words for the connection.
public enum StatusText {
    /// How `/me` says this device got in: "Signed in as vern through Tailscale", "Signed in on this Mac" (loopback on
    /// voyager), "Open: Enchiridion isn't checking devices".
    public static func signedIn(_ me: Me) -> String {
        switch me.scheme {
        case "tailscale":
            guard let name = me.device?.name, !name.isEmpty else { return "Signed in through Tailscale" }
            return "Signed in as \(name) through Tailscale"
        case "local":
            return "Signed in on this Mac"
        case "open":
            return "Open: Enchiridion isn't checking devices"
        default:
            return "Signed in through \(me.scheme)"
        }
    }

    /// A failed check in a few words: "Tailscale is off", "Not on Enchiridion's list".
    public static func problem(_ error: EnchiridionError) -> String {
        switch error {
        case .tailscaleOff: "Tailscale is off"
        case .offline: "You're offline"
        case .unreachable: "Can't reach voyager"
        case .restarting: "Enchiridion is restarting"
        case .unauthorized(let device): device == nil ? "Can't tell which device this is" : "Not on Enchiridion's list"
        case .forbidden: "voyager refused the connection"
        case .notFound, .rejected, .server, .decoding: "Couldn't check this device"
        }
    }

    /// The status line: a failure wins over an older answer; "Checking…" until the first answer; nil before any
    /// check.
    public static func connection(me: Me?, error: EnchiridionError?, checking: Bool) -> String? {
        if let error { return problem(error) }
        if let me { return signedIn(me) }
        return checking ? "Checking…" : nil
    }
}
