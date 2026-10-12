import EnchiridionKit
import Foundation

/// What the app's Siri and Shortcuts actions do, kept here so the target's App Intents stay glue: find records, pick
/// one at random, save a link. Each call answers or throws; nothing is kept between them.
public struct RecordShortcuts: Sendable {
    private let client: EnchiridionClient
    private let fallbackSlug: @Sendable () -> String

    public init(environment: AppEnvironment, role: ClientRole = .app) {
        client = environment.client(role: role)
        fallbackSlug = environment.fallbackSlug
    }

    /// What to say when an action failed: the error's own message (Tailscale off, not on the list, …).
    public static func message(for error: any Error) -> String {
        EnchiridionError.classify(error)?.message ?? "Something went wrong."
    }

    /// Hybrid search, as the library's: text and meaning.
    public func find(_ query: String, limit: Int = 20) async throws -> [ListRecord] {
        try await client.search(query, limit: limit)
    }

    /// The newest records, for a picker before anything is typed.
    public func recent(limit: Int = 20) async throws -> [ListRecord] {
        var query = ListQuery.index
        query.limit = limit
        return try await client.list(query)
    }

    /// The record with `id`.
    public func record(id: Int) async throws -> Record {
        try await client.record(id: id).record
    }

    /// A record picked at random from the library (curated ones only, by default); nil when there are none.
    public func random(curatedOnly: Bool = true,
                       using pick: @Sendable ([ListRecord]) -> ListRecord? = { $0.randomElement() })
        async throws -> ListRecord? {
        pick(try await candidates(curatedOnly: curatedOnly))
    }

    /// Up to `count` different records picked at random, in the order picked: the widget's day of records from one
    /// request.
    public func sample(_ count: Int, curatedOnly: Bool = true,
                       using shuffle: @Sendable ([ListRecord]) -> [ListRecord] = { $0.shuffled() })
        async throws -> [ListRecord] {
        Array(shuffle(try await candidates(curatedOnly: curatedOnly)).prefix(count))
    }

    private func candidates(curatedOnly: Bool) async throws -> [ListRecord] {
        var query = ListQuery.index
        query.filters.isCurated = curatedOnly ? true : nil
        return try await client.list(query)
    }

    /// Saves a link as a new artifact, as the share card would with nothing edited: the title given, else the one
    /// found (`title` from the page's metadata, fetched by the caller), the note as its notes. Idempotent by slug like
    /// every create (`RecordCreation`).
    @MainActor public func save(url: URL, title: String?, note: String?) async throws -> Record {
        var draft = ShareDraft(ShareInput(url: url, title: title.flatMap(ShareInput.nonEmpty)))
        draft.note = note ?? ""
        let creation = RecordCreation(client: client, fallback: fallbackSlug)
        return try await creation.create(draft.input(slug: ""), base: draft.slugBase)
    }
}
