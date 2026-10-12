import Foundation

/// Everything `EnchiridionClient` throws, besides `CancellationError` (what `URLError.cancelled` becomes).
public enum EnchiridionError: Error, Sendable, Equatable {
    /// URLError -1003 cannotFindHost, -1006 dnsLookupFailed: `*.chsmc.tools` resolves through the tailnet, so with
    /// Tailscale off the lookup fails at once.
    case tailscaleOff
    /// -1001 timedOut, -1004 cannotConnectToHost, -1005 networkConnectionLost, and any other transport failure.
    case unreachable
    /// -1009 notConnectedToInternet, -1020 dataNotAllowed, -1018 internationalRoamingOff, and TLS failures
    /// (-1200 … -1206: a captive portal reads as offline).
    case offline
    /// HTTP 502 from Caddy: the API isn't listening (pm2 restarting it, voyager booting).
    case restarting
    /// 401. `device` is set when the server knew the device through Tailscale but it isn't on the list.
    case unauthorized(device: Device?)
    /// 403: Caddy refusing a caller from outside the tailnet.
    case forbidden
    /// 404. Record lookups answer with a plain-text body.
    case notFound
    /// Any other 4xx, with the server's message.
    case rejected(status: Int, message: String)
    /// A 5xx other than 502, with the server's message. Enchiridion answers validation failures and duplicate slugs
    /// with 500, so these are not transient: sending the same request again fails the same way.
    case server(status: Int, message: String)
    /// A 2xx body this build couldn't read (or a request it couldn't encode); the text is for logs.
    case decoding(String)

    /// Worth retrying later without changing anything: the network or the server's process, never the request.
    public var isTransient: Bool {
        switch self {
        case .tailscaleOff, .unreachable, .offline, .restarting: true
        case .unauthorized, .forbidden, .notFound, .rejected, .server, .decoding: false
        }
    }

    /// Plain words for the UI. The server's own message, for `rejected` and `server`, is cut to 250 characters, as
    /// the web cuts its toasts.
    public var message: String {
        switch self {
        case .tailscaleOff: "Tailscale is off. Turn it on to reach Enchiridion."
        case .unreachable: "Can't reach voyager."
        case .offline: "You're offline."
        case .restarting: "Enchiridion is restarting."
        case .unauthorized(let device):
            device == nil ? "Enchiridion couldn't tell which device this is. Is Tailscale on?"
                : "This iPhone isn't on Enchiridion's list yet."
        case .forbidden: "voyager refused the connection. Is this device on the tailnet?"
        case .notFound: "That record couldn't be found."
        case .rejected(_, let message), .server(_, let message): String(message.prefix(Self.messageLimit))
        case .decoding: "Enchiridion sent something this app couldn't read."
        }
    }

    static let messageLimit = 250
}

extension EnchiridionError: LocalizedError {
    public var errorDescription: String? { message }
}

// MARK: Mapping

extension EnchiridionError {
    static let tailscaleOffCodes: Set<URLError.Code> = [.cannotFindHost, .dnsLookupFailed]
    static let unreachableCodes: Set<URLError.Code> = [.timedOut, .cannotConnectToHost, .networkConnectionLost]
    static let offlineCodes: Set<URLError.Code> = [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff]

    /// Maps whatever a transport threw to an `EnchiridionError`, or to `CancellationError`. An error that is already
    /// one of those passes through.
    public static func fromTransport(_ error: any Error) -> any Error {
        if error is EnchiridionError || error is CancellationError { return error }
        guard let urlError = error as? URLError else { return EnchiridionError.unreachable }
        let code = urlError.code
        if code == .cancelled { return CancellationError() }
        if tailscaleOffCodes.contains(code) { return EnchiridionError.tailscaleOff }
        if unreachableCodes.contains(code) { return EnchiridionError.unreachable }
        // -1200 … -1206: secureConnectionFailed through clientCertificateRequired.
        if offlineCodes.contains(code) || (-1206 ... -1200).contains(code.rawValue) { return EnchiridionError.offline }
        return EnchiridionError.unreachable
    }

    /// Maps a non-2xx response to an error, reading the server's message from whichever body shape it sent.
    public static func fromResponse(_ response: HTTPURLResponse, body: Data) -> EnchiridionError {
        let status = response.statusCode
        let errorBody = ErrorBody.decode(body)
        switch status {
        case 401:
            return .unauthorized(device: errorBody?.device)
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 502:
            return .restarting
        case 400 ..< 500:
            return .rejected(status: status,
                             message: serverMessage(errorBody, body) ?? "Enchiridion couldn't accept that request.")
        default:
            return .server(status: status, message: serverMessage(errorBody, body) ?? "Enchiridion ran into a problem.")
        }
    }

    /// The JSON body's message, else a short plain-text body (Express's `res.send` text), never an HTML page.
    private static func serverMessage(_ errorBody: ErrorBody?, _ body: Data) -> String? {
        if let message = errorBody?.message { return message }
        guard errorBody == nil, let text = String(data: body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty, !text.hasPrefix("<")
        else { return nil }
        return text
    }
}

/// An error response's body, in any of the shapes the server sends:
/// - `{message}`: Express's `errorHandler` (zod failures, drizzle errors, anything thrown);
/// - `{error: "text"}`: the search routes;
/// - `{error: {code, message}, message, device}`: the auth middleware's 401, whose top-level `message` keeps the web
///   app's toast readable and whose `device` names a device that isn't on the list.
struct ErrorBody: Decodable, Equatable {
    var message: String?
    var code: String?
    var device: Device?

    private enum CodingKeys: String, CodingKey {
        case message, error, device
    }

    private struct Detail: Decodable {
        var code: String?
        var message: String?
    }

    /// nil unless `data` is a JSON object.
    static func decode(_ data: Data) -> ErrorBody? {
        try? JSONDecoder().decode(ErrorBody.self, from: data)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        device = try? container.decodeIfPresent(Device.self, forKey: .device)
        let detail = try? container.decodeIfPresent(Detail.self, forKey: .error)
        code = detail?.code
        let messages = [
            try? container.decodeIfPresent(String.self, forKey: .message),
            try? container.decodeIfPresent(String.self, forKey: .error),
            detail?.message,
        ]
        message = messages.lazy.compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
