import EnchiridionKit
import struct EnchiridionKit.Predicate
import Foundation
import Observation

/// A link a new record will get once it's saved (the web's add form's `links`): the record it points at and how.
/// The server stores only canonical predicates and flips the others itself, so any predicate can be offered.
public struct PendingLink: Hashable, Sendable, Identifiable {
    public var targetID: Int
    public var title: String?
    public var slug: String
    public var type: RecordType
    public var predicate: Predicate

    public init(targetID: Int, title: String?, slug: String, type: RecordType, predicate: Predicate) {
        self.targetID = targetID
        self.title = title
        self.slug = slug
        self.type = type
        self.predicate = predicate
    }

    public init(_ row: ListRecord, predicate: Predicate) {
        self.init(targetID: row.id, title: row.title, slug: row.slug, type: row.type, predicate: predicate)
    }

    public init(_ record: Record, predicate: Predicate) {
        self.init(targetID: record.id, title: record.title, slug: record.slug, type: record.type, predicate: predicate)
    }

    /// One link per target: choosing a record already linked changes how it's linked.
    public var id: Int { targetID }

    /// The target's title, else its slug.
    public var displayTitle: String {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return slug }
        return title
    }

    /// The `PUT /link` for a record saved with this id.
    public func input(sourceID: Int) -> LinkInput {
        LinkInput(sourceId: sourceID, targetId: targetID, predicate: predicate)
    }
}

extension PendingLink {
    /// Sends each link from the record saved as `recordID`; returns the ones that failed (`PUT /link` upserts, so
    /// sending one again that landed after all is harmless).
    static func send(_ links: [PendingLink], from recordID: Int, client: EnchiridionClient) async -> [PendingLink] {
        var failed: [PendingLink] = []
        for link in links {
            do {
                _ = try await client.putLink(link.input(sourceID: recordID))
            } catch {
                failed.append(link)
            }
        }
        return failed
    }
}

extension Array where Element == PendingLink {
    /// Adds a link, or changes how an already linked record is linked.
    public mutating func link(_ link: PendingLink) {
        if let index = firstIndex(where: { $0.id == link.id }) {
            self[index] = link
        } else {
            append(link)
        }
    }
}

extension Predicate {
    /// The relationships a new link can have, as the web's link picker offers them: the canonical predicates, in
    /// vocabulary order (created by, via, edited by, contained by, quotes, has format, tagged with, references, about,
    /// related to, same as).
    public static var linkOptions: [Predicate] {
        vocabulary.filter(\.canonical).map(\.slug)
    }

    /// The name as a menu shows it: "Created by".
    public var menuName: String {
        let name = self.name
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// Finds records to link to: hybrid search after the typing pauses (`Timings.searchDebounce`), the newest answer
/// winning. An empty query shows nothing. Used by the share card's and the editor's link pickers.
@MainActor @Observable
public final class RecordSearchModel {
    /// What's typed. Setting it starts (or restarts) the debounce.
    public var query = "" {
        didSet { if query != oldValue { schedule() } }
    }
    public private(set) var results: [ListRecord] = []
    public private(set) var isSearching = false
    public private(set) var error: EnchiridionError?

    /// Records to leave out of the results (the record being linked from, say).
    @ObservationIgnored public var excludedIDs: Set<Int> = []

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let client: EnchiridionClient
    @ObservationIgnored private var task: Task<Void, Never>?

    /// How many results a pick list shows.
    public nonisolated static let limit = 30

    public init(environment: AppEnvironment, role: ClientRole = .app) {
        self.environment = environment
        client = environment.client(role: role)
    }

    private func schedule() {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            isSearching = false
            error = nil
            return
        }
        isSearching = true
        let environment = environment
        let client = client
        task = Task { [weak self] in
            do {
                try await environment.sleep(for: environment.timings.searchDebounce)
                let found = try await client.search(text, limit: Self.limit)
                guard !Task.isCancelled, let self else { return }
                self.results = found.filter { !self.excludedIDs.contains($0.id) }
                self.error = nil
                self.isSearching = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.error = EnchiridionError.classify(error)
                self.isSearching = false
            }
        }
    }

    /// Waits for the search in flight, if any (tests).
    public func settle() async {
        await task?.value
    }
}
