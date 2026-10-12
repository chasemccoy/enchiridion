import EnchiridionCore
import EnchiridionKit
import Foundation
import Synchronization
import Testing

/// A canned HTTP response.
struct StubResponse: Sendable {
    var status: Int
    var contentType: String
    var body: Data

    init(status: Int = 200, contentType: String = "application/json", body: Data = Data()) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    /// `value` as the server would send it (every wire type is Codable with the server's keys).
    static func json(_ value: some Encodable, status: Int = 200) -> StubResponse {
        StubResponse(status: status, body: (try? JSONEncoder().encode(value)) ?? Data())
    }

    static func raw(_ json: String, status: Int = 200) -> StubResponse {
        StubResponse(status: status, body: Data(json.utf8))
    }

    /// Express's `res.status(404).send("Record not found")`.
    static func text(_ text: String, status: Int) -> StubResponse {
        StubResponse(status: status, contentType: "text/html; charset=utf-8", body: Data(text.utf8))
    }

    static let notFound = text("Record not found", status: 404)
}

/// A request as a test asserts on it.
struct StubRequest: Sendable {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data?

    /// "GET /record/4".
    var route: String { "\(method) \(path)" }

    init(_ request: URLRequest) {
        method = request.httpMethod ?? "GET"
        let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        path = components?.path ?? ""
        query = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { _, last in last }
        headers = request.allHTTPHeaderFields ?? [:]
        body = request.httpBody
    }

    /// The JSON body as an object (explicit nulls appear as `NSNull`).
    func json() -> [String: Any] {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) else { return [:] }
        return object as? [String: Any] ?? [:]
    }
}

/// Records every request and answers each from a handler, or throws what the handler throws (a URLError, say).
actor StubTransport: HTTPTransport {
    typealias Handler = @Sendable (StubRequest) throws -> StubResponse

    private var handler: Handler
    private(set) var requests: [StubRequest] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func respond(with handler: @escaping Handler) {
        self.handler = handler
    }

    /// "GET /record/4" for each request so far.
    var routes: [String] { requests.map(\.route) }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let stub = StubRequest(request)
        requests.append(stub)
        let reply = try handler(stub)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": reply.contentType])!
        return (reply.body, response)
    }
}

/// Answers through a `StubTransport` (whose handler decides, and records the request, when it arrives), but holds back
/// the answers to requests `holding` matches until `release()`: the server has acted, and its answer is still on the
/// way. A held request that is cancelled throws `CancellationError`, as URLSession's do.
actor HoldingTransport: HTTPTransport {
    let stub: StubTransport
    private var holding: @Sendable (StubRequest) -> Bool
    private var held: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var cancelled: Set<Int> = []
    private var nextID = 0

    init(_ stub: StubTransport, holding: @escaping @Sendable (StubRequest) -> Bool = { _ in false }) {
        self.stub = stub
        self.holding = holding
    }

    /// Answers held right now.
    var heldCount: Int { held.count }

    func hold(_ holding: @escaping @Sendable (StubRequest) -> Bool) {
        self.holding = holding
    }

    /// Lets every held answer through, and holds nothing more.
    func release() {
        holding = { _ in false }
        let waiting = held
        held = [:]
        for continuation in waiting.values { continuation.resume() }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let answer = try await stub.data(for: request)
        guard holding(StubRequest(request)) else { return answer }
        nextID += 1
        let id = nextID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if cancelled.remove(id) != nil {
                    continuation.resume(throwing: CancellationError())
                } else {
                    held[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
        return answer
    }

    private func cancel(_ id: Int) {
        if let continuation = held.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        } else {
            cancelled.insert(id)
        }
    }

    /// Waits (in real time, up to 5 s) until `count` answers are held.
    func waitUntilHeld(_ count: Int = 1, sourceLocation: SourceLocation = #_sourceLocation) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while held.count != count {
            if ContinuousClock.now > deadline {
                Issue.record("Timed out waiting for \(count) held answers (have \(held.count))",
                             sourceLocation: sourceLocation)
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

/// A server holding records, for create and edit flows. A create inserts (ids from 42); an update changes only the
/// keys it sends (404 for an id it doesn't hold); a lookup answers by slug, or by id (`GET /record/:id`).
/// `loseNextAnswer()` makes the next `PUT` take effect and then time out, and takes lookups down with it until
/// `recover()`: the network dropped mid-save. `lookupsToo: false` loses only that answer.
final class FakeRecordServer: Sendable {
    private struct State {
        var records: [Record] = []
        var nextID = 42
        var loseAnswer = false
        var lookupsDown = false
        var lookupsFollow = true
        var puts: [[String: Any]] = []
    }

    private let state = Mutex(State())

    var records: [Record] { state.withLock { $0.records } }
    /// The `PUT /record` bodies, in order.
    var puts: [[String: Any]] { state.withLock { $0.puts } }

    func loseNextAnswer(lookupsToo: Bool = true) {
        state.withLock {
            $0.loseAnswer = true
            $0.lookupsFollow = lookupsToo
        }
    }
    func recover() { state.withLock { $0.lookupsDown = false } }
    /// A record that was there before the test.
    func seed(_ record: Record) {
        state.withLock { state in
            state.records.append(record)
            state.nextID = max(state.nextID, record.id + 1)
        }
    }

    /// A change made elsewhere (the web, an agent) to the stored record `id`.
    func edit(_ id: Int, _ change: (inout Record) -> Void) {
        state.withLock { state in
            guard let index = state.records.firstIndex(where: { $0.id == id }) else { return }
            change(&state.records[index])
        }
    }

    func handle(_ request: StubRequest) throws -> StubResponse {
        try state.withLock { state in
            if request.method == "GET", request.path.hasPrefix("/record/slug/") {
                if state.lookupsDown { throw URLError(.timedOut) }
                let slug = String(request.path.dropFirst("/record/slug/".count))
                return state.records.first { $0.slug == slug }.map { .json($0) } ?? .notFound
            }
            if request.method == "GET", request.path.hasPrefix("/record/"),
               let id = Int(request.path.dropFirst("/record/".count)) {
                if state.lookupsDown { throw URLError(.timedOut) }
                return state.records.first { $0.id == id }.map { .json(RecordDetail(record: $0)) } ?? .notFound
            }
            guard request.route == "PUT /record" else { return .notFound }
            let body = request.json()
            state.puts.append(body)
            var record: Record
            if let id = body["id"] as? Int {
                guard let index = state.records.firstIndex(where: { $0.id == id }) else { return .notFound }
                record = state.records[index]
                Self.apply(body, to: &record)
                state.records[index] = record
            } else {
                record = Record(id: state.nextID, slug: body["slug"] as? String ?? "",
                                recordCreatedAt: "2026-10-11 22:00:00")
                state.nextID += 1
                Self.apply(body, to: &record)
                state.records.append(record)
            }
            if state.loseAnswer {
                state.loseAnswer = false
                state.lookupsDown = state.lookupsFollow
                throw URLError(.timedOut)
            }
            return .json(record)
        }
    }

    private static func apply(_ body: [String: Any], to record: inout Record) {
        func text(_ key: String) -> String?? {
            guard let value = body[key] else { return nil }
            return .some(value as? String)
        }
        if let slug = body["slug"] as? String { record.slug = slug }
        if let type = body["type"] as? String { record.type = RecordType(rawValue: type) }
        if let title = text("title") { record.title = title }
        if let url = text("url") { record.url = url }
        if let summary = text("summary") { record.summary = summary }
        if let content = text("content") { record.content = content }
        if let notes = text("notes") { record.notes = notes }
        if let isCurated = body["isCurated"] as? Bool { record.isCurated = isCurated }
        if let source = body["source"] as? String { record.source = RecordSource(rawValue: source) }
    }
}

extension AppEnvironment {
    static let testServer = URL(string: "https://enchiridion.example.test")!

    /// No waiting, UTC month headers, a fixed fallback slug and a fixed now.
    static func test(_ transport: any HTTPTransport, clock: any Clock<Duration> = ContinuousClock(),
                     timings: Timings = .immediate, timeZone: TimeZone = .gmt,
                     fallbackSlug: String = "note-0000beef") -> AppEnvironment {
        AppEnvironment(server: testServer, transport: transport, appVersion: "0.1",
                       now: { Date(timeIntervalSince1970: 1_791_763_200) }, clock: clock, timeZone: timeZone,
                       timings: timings, fallbackSlug: { fallbackSlug })
    }
}
