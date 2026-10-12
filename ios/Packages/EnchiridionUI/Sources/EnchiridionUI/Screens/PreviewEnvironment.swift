#if DEBUG
import EnchiridionCore
import EnchiridionKit
import Foundation

/// An in-memory Enchiridion API for previews and DEBUG demos: it serves `PreviewSamples` (and the records they link
/// to) and keeps creates, edits, curation and deletes in memory. It never touches the network, so a preview can't
/// write to voyager.
public actor PreviewTransport: HTTPTransport {
    /// What the server does.
    public enum Scenario: Hashable, Sendable {
        /// Answers everything from the samples.
        case library
        /// An empty library.
        case empty
        /// Every route but `/info` refuses this device: a 401 naming `PreviewSamples.device`.
        case notAllowed
        /// The host doesn't resolve, as with Tailscale off.
        case tailscaleOff
    }

    private let scenario: Scenario
    private let latency: Duration
    private var rows: [Int: ListRecord]
    private var nextID: Int

    public init(_ scenario: Scenario = .library, latency: Duration = .milliseconds(150)) {
        self.scenario = scenario
        self.latency = latency
        let seeded = scenario == .empty ? [] : Self.seed()
        rows = Dictionary(uniqueKeysWithValues: seeded.map { ($0.id, $0) })
        nextID = (seeded.map(\.id).max() ?? 0) + 1
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: latency)
        let url = request.url ?? URL(string: "https://enchiridion.preview.invalid")!
        let method = request.httpMethod ?? "GET"
        let parts = url.path(percentEncoded: false).split(separator: "/").map(String.init)

        if scenario == .tailscaleOff { throw URLError(.cannotFindHost) }
        if parts == ["info"] { return try json(url, Info(auth: ["tailscale"])) }
        if scenario == .notAllowed { return try notAllowed(url) }

        switch Route(method: method, parts: parts) {
        case .me:
            return try json(url, Me(scheme: "tailscale", device: PreviewSamples.device, user: "preview@example.com"))
        case .index:
            return try json(url, index(hidingUntitledChildren: Self.hidesUntitledChildren(request.httpBody)))
        case .search:
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value ?? ""
            return try json(url, search(query))
        case .recordBySlug(let slug):
            guard let row = rows.values.first(where: { $0.slug == slug }) else { return notFound(url) }
            return try json(url, Self.record(row))
        case .links(let id):
            guard rows[id] != nil else { return notFound(url) }
            return try json(url, links(id))
        case .record(let id):
            guard let detail = detail(id) else { return notFound(url) }
            return try json(url, detail)
        case .save:
            return try save(url, body: request.httpBody)
        case .delete(let id):
            return try json(url, rows.removeValue(forKey: id).map { [Self.record($0)] } ?? [])
        case .deleteMedia(let id):
            let media = rows[id]?.media ?? []
            rows[id]?.media = []
            return try json(url, media)
        case nil:
            return notFound(url)
        }
    }

    /// The routes the client calls, from a method and the path's segments.
    private enum Route {
        case me, index, search, save
        case recordBySlug(String)
        case links(Int)
        case record(Int)
        case delete(Int)
        case deleteMedia(Int)

        init?(method: String, parts: [String]) {
            // The numeric segment of `record/<id>`, `record/<id>/links` and `media/record/<id>`.
            let id = parts.last(where: { Int($0) != nil }).flatMap { Int($0) }
            switch (method, parts.first ?? "", parts.count, id) {
            case ("GET", "me", 1, _): self = .me
            case ("POST", "records", 1, _): self = .index
            case ("GET", "search", 2, _) where parts[1] == "hybrid": self = .search
            case ("GET", "record", 3, _) where parts[1] == "slug": self = .recordBySlug(parts[2])
            case ("GET", "record", 3, let id?) where parts[2] == "links": self = .links(id)
            case ("GET", "record", 2, let id?): self = .record(id)
            case ("PUT", "record", 1, _): self = .save
            case ("DELETE", "record", 2, let id?): self = .delete(id)
            case ("DELETE", "media", 3, let id?) where parts[1] == "record": self = .deleteMedia(id)
            default: return nil
            }
        }
    }

    // MARK: Routes

    private func index(hidingUntitledChildren: Bool) -> [ListRecord] {
        rows.values
            .filter { !hidingUntitledChildren || $0.title.nonBlank != nil || $0.parent == nil }
            .sorted { lhs, rhs in
                lhs.recordCreatedAt == rhs.recordCreatedAt
                    ? lhs.slug < rhs.slug
                    : lhs.recordCreatedAt > rhs.recordCreatedAt
            }
    }

    private func search(_ query: String) -> [ListRecord] {
        let needle = query.lowercased()
        return index(hidingUntitledChildren: false).compactMap { row in
            let haystack = [row.title, row.summary, row.content, row.notes].compactMap(\.self).joined(separator: " ")
            guard haystack.lowercased().contains(needle) else { return nil }
            var hit = row
            hit.score = 0.5
            return hit
        }
    }

    private func detail(_ id: Int) -> RecordDetail? {
        guard let row = rows[id] else { return nil }
        let outgoing = row.outgoingLinks.compactMap { link in
            rows[link.target.id].map { RecordDetail.OutgoingLink(predicate: link.predicate, target: Self.record($0)) }
        }
        return RecordDetail(record: Self.record(row), outgoingLinks: outgoing, media: row.media)
    }

    private func links(_ id: Int) -> LinksBundle {
        let stamp: DBTimestamp = "2026-10-01 12:00:00"
        let outgoing = (rows[id]?.outgoingLinks ?? []).enumerated().map { index, link in
            LinksBundle.OutgoingLink(
                link: Link(id: id * 100 + index, sourceId: id, targetId: link.target.id, predicate: link.predicate,
                           recordCreatedAt: stamp),
                target: .init(title: link.target.title, slug: link.target.slug))
        }
        let incoming = rows.values.sorted { $0.id < $1.id }.flatMap { source in
            source.outgoingLinks.enumerated().filter { $0.element.target.id == id }.map { index, link in
                LinksBundle.IncomingLink(
                    link: Link(id: source.id * 100 + index, sourceId: source.id, targetId: id,
                               predicate: link.predicate, recordCreatedAt: stamp),
                    source: .init(title: source.title, slug: source.slug, content: source.content))
            }
        }
        return LinksBundle(id: id, outgoingLinks: outgoing, incomingLinks: incoming)
    }

    /// `PUT /record`: an update merges the keys it sends (a JSON `null` clears one, an absent key keeps it); a create
    /// needs a slug no record has, as the server's unique index does.
    private func save(_ url: URL, body: Data?) throws -> (Data, HTTPURLResponse) {
        guard let body, let fields = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return try json(url, ["message": "Expected a JSON object"], status: 500)
        }
        let now = DBTimestamp(Date())
        var row: ListRecord
        if let id = fields["id"] as? Int {
            guard let existing = rows[id] else { return notFound(url) }
            row = existing
        } else {
            let slug = (fields["slug"] as? String) ?? ""
            guard !slug.isEmpty, !rows.values.contains(where: { $0.slug == slug }) else {
                return try json(url, ["message": "Failed query: UNIQUE constraint failed: records.slug"], status: 500)
            }
            row = ListRecord(id: nextID, slug: slug, recordCreatedAt: now)
            nextID += 1
        }
        func text(_ key: String) -> String?? {
            guard let value = fields[key] else { return .none }
            return .some(value as? String)
        }
        if let slug = fields["slug"] as? String, !slug.isEmpty { row.slug = slug }
        if let type = fields["type"] as? String { row.type = RecordType(rawValue: type) }
        if let isCurated = fields["isCurated"] as? Bool { row.isCurated = isCurated }
        if case .some(let value) = text("title") { row.title = value }
        if case .some(let value) = text("url") { row.url = value }
        if case .some(let value) = text("summary") { row.summary = value }
        if case .some(let value) = text("content") { row.content = value }
        if case .some(let value) = text("notes") { row.notes = value }
        if case .some(let value) = text("source") { row.source = value.map(RecordSource.init(rawValue:)) }
        row.recordUpdatedAt = now
        rows[row.id] = row
        return try json(url, Self.record(row))
    }

    // MARK: Answers

    private func json(_ url: URL, _ value: some Encodable, status: Int = 200) throws -> (Data, HTTPURLResponse) {
        (try JSONEncoder().encode(value), Self.response(url, status: status))
    }

    private func notFound(_ url: URL) -> (Data, HTTPURLResponse) {
        (Data("<!DOCTYPE html><title>Not found</title>".utf8), Self.response(url, status: 404))
    }

    private func notAllowed(_ url: URL) throws -> (Data, HTTPURLResponse) {
        struct Refusal: Encodable {
            struct Detail: Encodable {
                var code: String
                var message: String
            }

            var error: Detail
            var message: String
            var device: Device
        }
        let message = "This device isn't on Enchiridion's list yet."
        return try json(url, Refusal(error: .init(code: "unauthorized", message: message), message: message,
                                     device: PreviewSamples.device), status: 401)
    }

    private static func response(_ url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"])!
    }

    private static func hidesUntitledChildren(_ body: Data?) -> Bool {
        guard let body, let query = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let filters = query["filters"] as? [String: Any]
        else { return false }
        return filters["hideUntitledChildren"] as? Bool ?? false
    }

    // MARK: Samples

    private static func record(_ row: ListRecord) -> Record {
        Record(id: row.id, slug: row.slug, type: row.type, title: row.title, url: row.url, isCurated: row.isCurated,
               summary: row.summary, content: row.content, notes: row.notes, source: row.source,
               recordCreatedAt: row.recordCreatedAt, recordUpdatedAt: row.recordUpdatedAt,
               contentCreatedAt: row.contentCreatedAt)
    }

    /// The samples, the article given its full content, and the records they link to that aren't samples themselves
    /// (a creator as an entity, a tag or format as a concept).
    private static func seed() -> [ListRecord] {
        var rows = PreviewSamples.listRecords.map { row in
            row.id == PreviewSamples.record.id ? row.merging(PreviewSamples.record) : row
        }
        var ids = Set(rows.map(\.id))
        for link in rows.flatMap(\.outgoingLinks) where ids.insert(link.target.id).inserted {
            rows.append(ListRecord(id: link.target.id, slug: link.target.slug, title: link.target.title,
                                   type: link.predicate == .createdBy ? .entity : .concept,
                                   recordCreatedAt: "2026-08-20 10:00:00", isCurated: true))
        }
        return rows
    }
}

extension AppEnvironment {
    /// An environment whose API is a `PreviewTransport` (DEBUG builds only): previews, and a demo mode for the app.
    public static func preview(_ scenario: PreviewTransport.Scenario = .library) -> AppEnvironment {
        AppEnvironment(server: URL(string: "https://enchiridion.preview.invalid")!,
                       transport: PreviewTransport(scenario), appVersion: "0.1")
    }
}
#endif
