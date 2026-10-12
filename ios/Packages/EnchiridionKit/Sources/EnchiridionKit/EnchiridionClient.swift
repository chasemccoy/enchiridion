import Foundation

/// Who is calling, for `X-Enchiridion-Client` and the timeout.
public enum ClientRole: String, Hashable, Sendable {
    case app, share
}

/// The HTTP client for Enchiridion's Express API, over an injected transport.
///
/// Every request carries `Accept: application/json` and `X-Enchiridion-Client: ios/<version> <role>`; every body is
/// JSON with `Content-Type: application/json` (Express parses nothing else into `req.body`). No request carries
/// `Origin` or credentials: voyager knows the device through Tailscale. Transport failures and non-2xx answers throw
/// `EnchiridionError` (or `CancellationError`).
public actor EnchiridionClient {
    public struct Configuration: Hashable, Sendable {
        /// The API's origin, e.g. `https://enchiridion-api.chsmc.tools`; paths are appended to it.
        public var server: URL
        public var role: ClientRole
        /// `CFBundleShortVersionString`.
        public var appVersion: String
        public var platform: String
        public var timeout: Duration

        /// `timeout` nil picks the role's.
        public init(server: URL, role: ClientRole, appVersion: String, platform: String = "ios",
                    timeout: Duration? = nil) {
            self.server = server
            self.role = role
            self.appVersion = appVersion
            self.platform = platform
            self.timeout = timeout ?? Self.timeout(for: role)
        }

        /// 30 s for the app; 10 s for the share extension, which the system ends if it lingers.
        public static func timeout(for role: ClientRole) -> Duration {
            switch role {
            case .app: .seconds(30)
            case .share: .seconds(10)
            }
        }

        /// `ios/0.1 app`.
        public var clientHeader: String { "\(platform)/\(appVersion) \(role.rawValue)" }
    }

    public nonisolated let configuration: Configuration
    private nonisolated let transport: any HTTPTransport

    public init(_ configuration: Configuration, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    // MARK: Identity

    /// `GET /info`, which never needs auth.
    public func info() async throws -> Info {
        try await perform(request("GET", "/info"), as: Info.self)
    }

    /// `GET /me`: who the server took this caller for. A 401 here means what it means anywhere else.
    public func me() async throws -> Me {
        try await perform(request("GET", "/me"), as: Me.self)
    }

    // MARK: Records

    /// `POST /records`: a bare array, no total. The app's index sends `ListQuery.index`.
    public func list(_ query: ListQuery) async throws -> [ListRecord] {
        try await perform(request("POST", "/records", body: query), as: [ListRecord].self)
    }

    /// `GET /search/hybrid`: text and semantic matches fused by rank, each row with its `score`. A blank query
    /// returns nothing without asking (the server would answer 400).
    public func search(_ q: String, limit: Int = 100) async throws -> [ListRecord] {
        let query = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))]
        return try await perform(request("GET", "/search/hybrid", query: items), as: [ListRecord].self)
    }

    /// `GET /record/:id`. A missing record throws `.notFound`.
    public func record(id: Int) async throws -> RecordDetail {
        try await perform(request("GET", "/record/\(id)"), as: RecordDetail.self)
    }

    /// `GET /record/slug/:slug`, nil when no record has the slug (a 404): how a new slug is checked for uniqueness.
    /// The server also sends `media` and `archives`; only the record's columns are kept.
    public func record(slug: String) async throws -> Record? {
        let (data, response) = try await exchange(request("GET", "/record/slug/" + Self.pathSegment(slug)))
        if response.statusCode == 404 { return nil }
        return try decode(Record.self, data: data, response: response)
    }

    /// `GET /record/:id/links`: every link touching the record, both ways. The server answers a missing record with
    /// 200 and an empty body, which throws `.notFound`.
    public func links(id: Int) async throws -> LinksBundle {
        let (data, response) = try await exchange(request("GET", "/record/\(id)/links"))
        if (200 ..< 300).contains(response.statusCode),
           data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            throw EnchiridionError.notFound
        }
        return try decode(LinksBundle.self, data: data, response: response)
    }

    /// `PUT /record`: creates the record (no `id`) or updates it, and returns the stored row. A taken or empty slug
    /// throws `.server(status: 500, …)`: check `record(slug:)` first.
    public func save(_ input: RecordInput) async throws -> Record {
        try await perform(request("PUT", "/record", body: input), as: Record.self)
    }

    /// `PUT /record` with only `{id, slug, isCurated}`, so nothing else the client may hold stale is written back.
    public func setCurated(id: Int, slug: String, _ isCurated: Bool) async throws -> Record {
        try await perform(request("PUT", "/record", body: CurationInput(id: id, slug: slug, isCurated: isCurated)),
                          as: Record.self)
    }

    /// `DELETE /record/:id`: the deleted rows, empty when there was none. Links, media rows and the archive row go with
    /// it, but the media files stay on disk: call `deleteMedia(recordID:)` first when the record has media.
    @discardableResult
    public func delete(id: Int) async throws -> [Record] {
        try await perform(request("DELETE", "/record/\(id)"), as: [Record].self)
    }

    /// `DELETE /media/record/:id`: moves the record's media files to voyager's Trash and deletes their rows.
    @discardableResult
    public func deleteMedia(recordID: Int) async throws -> [Media] {
        try await perform(request("DELETE", "/media/record/\(recordID)"), as: [Media].self)
    }

    // MARK: Links

    /// `PUT /link`: the stored link, which may be flipped to the canonical direction.
    public func putLink(_ input: LinkInput) async throws -> Link {
        try await perform(request("PUT", "/link", body: input), as: Link.self)
    }

    /// `DELETE /link/:id`: the deleted rows, empty when there was none.
    @discardableResult
    public func deleteLink(id: Int) async throws -> [Link] {
        try await perform(request("DELETE", "/link/\(id)"), as: [Link].self)
    }

    // MARK: Plumbing

    private struct CurationInput: Encodable {
        var id: Int
        var slug: String
        var isCurated: Bool
    }

    nonisolated func request(_ method: String, _ path: String, query: [URLQueryItem] = []) -> URLRequest {
        request(method, path, query: query, bodyData: nil)
    }

    nonisolated func request(_ method: String, _ path: String, body: some Encodable) throws -> URLRequest {
        let data: Data
        do {
            let encoder = JSONEncoder()
            // Sorted keys keep bodies stable for logs and tests; unescaped slashes keep URLs readable.
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            data = try encoder.encode(body)
        } catch {
            throw EnchiridionError.decoding("Couldn't encode the request: \(error)")
        }
        return request(method, path, query: [], bodyData: data)
    }

    private nonisolated func request(_ method: String, _ path: String, query: [URLQueryItem],
                                     bodyData: Data?) -> URLRequest {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = Self.seconds(configuration.timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.clientHeader, forHTTPHeaderField: "X-Enchiridion-Client")
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }
        return request
    }

    /// `path` must already be percent-encoded. Query values are encoded here, `+` included: Express reads a bare `+`
    /// in a query as a space.
    private nonisolated func url(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: configuration.server, resolvingAgainstBaseURL: false) ?? URLComponents()
        let base = components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast()) : components.percentEncodedPath
        components.percentEncodedPath = base + path
        components.percentEncodedQuery = query.isEmpty ? nil : query.map { item in
            "\(Self.queryComponent(item.name))=\(Self.queryComponent(item.value ?? ""))"
        }.joined(separator: "&")
        components.fragment = nil
        return components.url ?? configuration.server
    }

    private static let queryAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#/")
        return allowed
    }()

    private static let segmentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/;?#")
        return allowed
    }()

    static func queryComponent(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? ""
    }

    static func pathSegment(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? ""
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let (seconds, attoseconds) = duration.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await exchange(request)
        return try decode(type, data: data, response: response)
    }

    private nonisolated func decode<T: Decodable>(_ type: T.Type, data: Data, response: HTTPURLResponse) throws -> T {
        guard (200 ..< 300).contains(response.statusCode) else {
            throw EnchiridionError.fromResponse(response, body: data)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw EnchiridionError.decoding("\(T.self): \(error)")
        }
    }

    private nonisolated func exchange(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.data(for: request)
        } catch {
            throw EnchiridionError.fromTransport(error)
        }
    }
}
