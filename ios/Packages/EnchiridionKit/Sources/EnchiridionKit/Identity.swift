import Foundation

/// `GET /info`, the one route that never needs auth, so the app can tell "can't reach Enchiridion" from "not
/// allowed". `auth` is `["tailscale"]` while voyager checks devices, `[]` while the API is open.
public struct Info: Codable, Hashable, Sendable {
    public var name: String
    public var auth: [String]

    public init(name: String = "enchiridion", auth: [String] = []) {
        self.name = name
        self.auth = auth
    }
}

/// A device as Tailscale names it: the node's stable id (a line of `~/.enchiridion/devices` on voyager) and its name.
public struct Device: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// `GET /me`: who the server took the caller for. `scheme` is `"tailscale"` (a listed device, or voyager itself),
/// `"local"` (loopback on voyager) or `"open"` (the API isn't checking devices); `device` and `user` are the
/// Tailscale node and login, when there is one.
public struct Me: Codable, Hashable, Sendable {
    public var scheme: String
    public var device: Device?
    public var user: String?

    public init(scheme: String, device: Device? = nil, user: String? = nil) {
        self.scheme = scheme
        self.device = device
        self.user = user
    }
}
