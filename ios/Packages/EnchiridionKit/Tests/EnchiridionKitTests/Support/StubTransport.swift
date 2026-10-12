import EnchiridionKit
import Foundation

/// A canned HTTP response.
struct StubResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data

    init(status: Int = 200, headers: [String: String] = ["Content-Type": "application/json"], json: String = "") {
        self.status = status
        self.headers = headers
        body = Data(json.utf8)
    }

    /// A body Express sent with `res.send(text)`: `text/html`, not JSON.
    static func text(_ text: String, status: Int) -> StubResponse {
        var response = StubResponse(status: status, headers: ["Content-Type": "text/html; charset=utf-8"])
        response.body = Data(text.utf8)
        return response
    }

    func response(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}

/// Records every request and answers each from a handler, or throws what the handler throws (a URLError, say).
actor StubTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest) throws -> StubResponse
    private let handler: Handler
    private var requests: [URLRequest] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// Answers every request with `response`.
    init(_ response: StubResponse) {
        self.init { _ in response }
    }

    /// Fails every request with `code`.
    init(failing code: URLError.Code) {
        self.init { _ in throw URLError(code) }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let reply = try handler(request)
        return (reply.body, reply.response(for: request))
    }

    func recorded() -> [URLRequest] { requests }

    func last() -> URLRequest? { requests.last }
}

extension EnchiridionClient {
    static let testServer = URL(string: "https://enchiridion.example.test")!

    static func test(_ transport: any HTTPTransport, role: ClientRole = .app) -> EnchiridionClient {
        EnchiridionClient(Configuration(server: testServer, role: role, appVersion: "0.1"), transport: transport)
    }
}

extension URLRequest {
    /// The body as a JSON object, for asserting on keys (explicit nulls appear as `NSNull`).
    func jsonObject() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: httpBody ?? Data(), options: [.fragmentsAllowed])
        return object as? [String: Any] ?? [:]
    }
}
