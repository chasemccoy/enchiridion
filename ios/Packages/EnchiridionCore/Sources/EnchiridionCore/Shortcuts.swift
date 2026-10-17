import EnchiridionKit
import Foundation

/// What the app's Siri and Shortcuts actions do, kept here so the target's App Intents stay glue: find records, pick
/// one at random, save a link. Each call answers or throws; nothing is kept between them.
public struct RecordShortcuts: Sendable {
    private let client: EnchiridionClient
    private let fallbackSlug: @Sendable () -> String
    private let environment: AppEnvironment

    public init(environment: AppEnvironment, role: ClientRole = .app) {
        self.environment = environment
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
    /// request, of one `type` when given. With `imagesEvery`, every other pick is a record with an image while there are any (few records have
    /// one, so a plain draw would rarely show a picture).
    public func sample(_ count: Int, curatedOnly: Bool = true, type: RecordType? = nil, imagesEvery: Bool = false,
                       using shuffle: @Sendable ([ListRecord]) -> [ListRecord] = { $0.shuffled() })
        async throws -> [ListRecord] {
        let shuffled = shuffle(try await candidates(curatedOnly: curatedOnly, type: type))
        return imagesEvery ? Self.alternatingImages(shuffled, count: count) : Array(shuffled.prefix(count))
    }

    /// `rows` in order, but with a record that has an image at every even position while any are left.
    static func alternatingImages(_ rows: [ListRecord], count: Int) -> [ListRecord] {
        var pictured = rows.filter(\.hasImage)[...]
        var plain = rows.filter { !$0.hasImage }[...]
        var picked: [ListRecord] = []
        while picked.count < count, !(pictured.isEmpty && plain.isEmpty) {
            let wantsImage = picked.count.isMultiple(of: 2)
            if wantsImage, let next = pictured.popFirst() ?? plain.popFirst() {
                picked.append(next)
            } else if let next = plain.popFirst() ?? pictured.popFirst() {
                picked.append(next)
            }
        }
        return picked
    }

    /// `sample`, tried up to `attempts` times `pause` apart while the failure is the network's (`isTransient`): a
    /// widget refreshing in the background may run before the phone's Tailscale tunnel is back up. Anything else
    /// throws at once.
    public func sampleRetrying(_ count: Int, curatedOnly: Bool = true, type: RecordType? = nil,
                               imagesEvery: Bool = false, attempts: Int = 3,
                               pause: Duration = .seconds(3)) async throws -> [ListRecord] {
        var attempt = 1
        while true {
            do {
                return try await sample(count, curatedOnly: curatedOnly, type: type, imagesEvery: imagesEvery)
            } catch {
                guard attempt < attempts, EnchiridionError.classify(error)?.isTransient == true else { throw error }
                attempt += 1
                try await environment.sleep(for: pause)
            }
        }
    }

    private func candidates(curatedOnly: Bool, type: RecordType? = nil) async throws -> [ListRecord] {
        var query = ListQuery.index
        query.filters.isCurated = curatedOnly ? true : nil
        query.filters.type = type
        return try await client.list(query)
    }

    /// A record the widget shows, with the record it sits in when it's a highlight (for "from <source> by <creator>").
    public struct Pick: Hashable, Sendable {
        public var record: ListRecord
        /// The record it's contained in or quotes, when that's in the library too.
        public var parent: ListRecord?

        public init(record: ListRecord, parent: ListRecord? = nil) {
            self.record = record
            self.parent = parent
        }
    }

    /// The widget's draw: `sampleRetrying`, but highlights (records inside another, untitled ones included, which the
    /// index hides) are always in the pool, curated or not; `curatedOnly` holds for everything else. Each pick carries
    /// its parent's row.
    public func widgetPicks(_ count: Int, curatedOnly: Bool = true, type: RecordType? = nil, imagesEvery: Bool = false,
                            attempts: Int = 3, pause: Duration = .seconds(3),
                            using shuffle: @Sendable ([ListRecord]) -> [ListRecord] = { $0.shuffled() })
        async throws -> [Pick] {
        var attempt = 1
        while true {
            do {
                var query = ListQuery.index
                query.filters.type = type
                query.filters.hideUntitledChildren = nil
                let all = try await client.list(query)
                let pool = all.filter { $0.parent != nil || !curatedOnly || $0.isCurated }
                let shuffled = shuffle(pool)
                let picked = imagesEvery ? Self.alternatingImages(shuffled, count: count) : Array(shuffled.prefix(count))
                let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                return picked.map { Pick(record: $0, parent: $0.parent.flatMap { byID[$0.id] }) }
            } catch {
                guard attempt < attempts, EnchiridionError.classify(error)?.isTransient == true else { throw error }
                attempt += 1
                try await environment.sleep(for: pause)
            }
        }
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

extension ListRecord {
    /// It has an image among its media.
    public var hasImage: Bool { media.contains(where: \.isImage) }
}
