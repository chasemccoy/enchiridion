import EnchiridionKit
import Foundation

/// Slugs for new records. The server requires a non-empty unique slug and never makes one, so the client does: from
/// the title the way the web does (`Slug.make`), else from the URL, else a `note-xxxxxxxx` fallback.
public enum RecordSlug {
    /// How many candidates (`base`, `base-2` … `base-20`) are checked before settling for a fallback.
    public static let maxProbes = 20
    /// URL-derived slugs are cut to this many characters, at a hyphen: a path can be arbitrarily long.
    public static let urlSlugLimit = 80

    /// The slug a record with this title and URL would like to have; "" when neither yields one (an emoji title and
    /// no URL), which means a fallback.
    public static func base(title: String?, url: String?) -> String {
        if let title {
            let slug = Slug.make(title)
            if !slug.isEmpty { return slug }
        }
        if let url { return fromURL(url) }
        return ""
    }

    /// The URL's host (without `www.`) and path as a slug: `https://www.example.com/posts/Tiny_Internets` gives
    /// `example-com-posts-tiny-internets`. Every non-alphanumeric character separates words, so dots and slashes
    /// don't run words together the way `Slug.make` alone would. A bare `example.com/article` is read with https
    /// assumed, as `WebAddress` reads it. "" for text that isn't a URL with a host.
    public static func fromURL(_ url: String) -> String {
        guard let text = WebAddress.withScheme(url), let components = URLComponents(string: text),
              let rawHost = components.host?.lowercased(), !rawHost.isEmpty
        else { return "" }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let path = components.percentEncodedPath.removingPercentEncoding ?? components.path
        let words = String((host + " " + path).map { $0.isLetter || $0.isNumber ? $0 : " " })
        return truncated(Slug.make(words), to: urlSlugLimit)
    }

    /// `slug` cut to at most `limit` characters, at the last hyphen that fits when there is one. Slugs are ASCII.
    static func truncated(_ slug: String, to limit: Int) -> String {
        guard slug.count > limit else { return slug }
        let head = slug.prefix(limit)
        guard let cut = head.lastIndex(of: "-"), cut > head.startIndex else { return String(head) }
        return String(head[..<cut])
    }

    /// The candidates in the order they're tried: `base`, `base-2`, `base-3` … up to `maxProbes` of them.
    public static func candidates(for base: String) -> [String] {
        [base] + (2 ... maxProbes).map { "\(base)-\($0)" }
    }

    /// The first candidate no record has, asking `GET /record/slug/:slug` for each; after `maxProbes` taken ones, a
    /// fresh fallback (not checked: 32 random bits). An empty base starts from a fallback. Lookup failures throw.
    static func unique(base: String, client: EnchiridionClient,
                       fallback: @Sendable () -> String) async throws -> String {
        let start = base.isEmpty ? fallback() : base
        for candidate in candidates(for: start) {
            if try await client.record(slug: candidate) == nil { return candidate }
        }
        return fallback()
    }
}

/// Creates records without making a second one when a create's answer was lost.
///
/// `PUT /record` without an id inserts every time it arrives, so a create that timed out may have landed. The slug is
/// the idempotency key: after a failure that might have landed, and again before a retry, the slug the create used is
/// looked up, and a record there matching the body that was sent (the same URL; the same title too, for a record
/// without one) is ours: the create succeeded. The form stays editable after a failure, so a retry may carry edits
/// made since: they go to the record that landed as an update, never as a second create. Edits are what differs from
/// the body that was sent, not from the record as stored now: the web or an agent may have changed it meanwhile, and
/// a field the draft didn't change is never written back. Main-actor bound because it remembers the attempt between
/// a model's saves.
@MainActor
final class RecordCreation {
    /// A create whose outcome isn't settled.
    enum Pending: Equatable {
        /// Sent (this body, its slug made from `base`), and the answer never came: it may have landed.
        case sent(RecordInput, base: String)
        /// Landed as `record` from the body `sent`, but edits made since haven't reached it yet. `attempted`: the
        /// fields of an update to it that failed, which may have landed all the same, so they go again whatever the
        /// draft holds now.
        case landed(Record, sent: RecordInput, attempted: Set<RecordInput.Field>)
    }

    private let client: EnchiridionClient
    private let fallback: @Sendable () -> String
    /// Set before the PUT; cleared once the record is known to hold the latest draft, or known not to exist (the
    /// server refused the create, or its slug turned out to be someone else's).
    private(set) var pending: Pending?
    /// The check after a lost answer got through and found nothing of ours under the slug. `pending` stays `.sent`
    /// (the slug is reused, and checked again, in case the request was only slow), but the save reads as not made.
    private var foundAbsent = false

    init(client: EnchiridionClient, fallback: @escaping @Sendable () -> String) {
        self.client = client
        self.fallback = fallback
    }

    /// The last attempt failed, but a record may be on the server all the same: a create whose answer was lost (or
    /// cancelled at a deadline) and whose check couldn't get through either, or one that landed before an update to it
    /// failed. The next attempt looks first, so it never makes a second record; a fresh form wouldn't know to, so the
    /// UI says it couldn't confirm the save rather than that nothing was saved.
    var isUnconfirmed: Bool {
        switch pending {
        case .landed: true
        case .sent: !foundAbsent
        case nil: false
        }
    }

    /// Creates `template` (its `slug` is replaced) under a unique slug made from `base`; or, when an earlier attempt
    /// landed, brings that record up to `template`.
    func create(_ template: RecordInput, base: String) async throws -> Record {
        var input = template
        switch pending {
        case .landed(let record, let sent, let attempted):
            return try await bringUp(record, sent: sent, attempted: attempted, to: template)
        case .sent(let sent, let sentBase):
            if let existing = try await client.record(slug: sent.slug) {
                if Self.isOurs(existing, sent) {
                    pending = .landed(existing, sent: sent, attempted: [])
                    return try await bringUp(existing, sent: sent, attempted: [], to: template)
                }
                // Someone else's record took it in the meantime, so the last create never landed: start over.
                pending = nil
                input.slug = try await RecordSlug.unique(base: base, client: client, fallback: fallback)
            } else if sentBase == base {
                // Still free, so the last create never landed: the probing already done stands.
                input.slug = sent.slug
            } else {
                // Never landed, and the title changed since: a slug from the new one.
                pending = nil
                input.slug = try await RecordSlug.unique(base: base, client: client, fallback: fallback)
            }
        case nil:
            input.slug = try await RecordSlug.unique(base: base, client: client, fallback: fallback)
        }

        pending = .sent(input, base: base)
        foundAbsent = false
        do {
            let record = try await client.save(input)
            pending = nil
            return record
        } catch {
            let failure = EnchiridionError.classify(error)
            if failure?.mightHaveLanded == true {
                do {
                    if let existing = try await client.record(slug: input.slug) {
                        if Self.isOurs(existing, input) {
                            pending = nil
                            return existing
                        }
                        // Someone else's record has the slug, so this create can't have landed under it.
                        pending = nil
                    } else {
                        foundAbsent = true
                    }
                } catch {
                    // The check failed the same way: it stays unconfirmed, and the next attempt checks first.
                }
            } else if let failure, failure.neverLanded {
                pending = nil
            }
            // Otherwise (cancelled at a deadline, an unreadable answer) it may have landed: `pending` stays.
            throw error
        }
    }

    /// The form closed with a create unsettled: forgets it, and finds the record it made so the rows can show it.
    /// Resolves to nil when it never landed, was deleted since, or couldn't be looked up. nil when nothing is pending.
    func abandon() -> Task<Record?, Never>? {
        guard let pending else { return nil }
        self.pending = nil
        let client = client
        return Task {
            switch pending {
            case .landed(let record, _, _):
                // Read back, for any update that landed since; the record as found when the read fails.
                do {
                    return try await client.record(id: record.id).record
                } catch EnchiridionError.notFound {
                    return nil
                } catch {
                    return record
                }
            case .sent(let sent, _):
                guard let existing = try? await client.record(slug: sent.slug), Self.isOurs(existing, sent) else {
                    return nil
                }
                return existing
            }
        }
    }

    /// `record` is what an earlier attempt created from `sent`; sends the fields `template` changed since that attempt
    /// (and `attempted`, an earlier update's) as an update to it. Diffing against `sent`, not the stored record, keeps
    /// a change made elsewhere since it landed: only the draft's own edits are written. With none, nothing is. An
    /// update can be sent again safely, so a failure keeps `pending` on the record, with these fields, for the next
    /// attempt.
    private func bringUp(_ record: Record, sent: RecordInput, attempted: Set<RecordInput.Field>,
                         to template: RecordInput) async throws -> Record {
        var update = template
        update.id = record.id
        update.slug = record.slug
        let changed = update.fieldsDiffering(from: sent).union(attempted)
        guard !changed.isEmpty else {
            pending = nil
            return record
        }
        do {
            let saved = try await client.save(update.only(changed))
            pending = nil
            return saved
        } catch EnchiridionError.notFound {
            // Deleted since it landed (on the web, say): the next attempt creates it again.
            pending = nil
            throw EnchiridionError.notFound
        } catch {
            pending = .landed(record, sent: sent, attempted: changed)
            throw error
        }
    }

    /// Whether `existing`, found under the slug a create used, is the record that create (`sent`) made. The slug was
    /// free a moment before, so the URL is enough; a record without one also has to match by title.
    static func isOurs(_ existing: Record, _ sent: RecordInput) -> Bool {
        existing.url == sent.url && (sent.url != nil || existing.title == sent.title)
    }
}

/// What a failed curate (`PUT /record {id, slug, isCurated}`) did. A lost answer (`mightHaveLanded`) may hide a curate
/// that landed, so the record is read back before the screen goes back to the old value: the server is the only copy,
/// and a list or switch showing otherwise would be wrong until the next reload.
enum RecordCuration {
    enum Outcome: Equatable {
        /// The record holds the value asked for: the curate landed, only its answer was lost.
        case landed(Record)
        /// The read-back answered 404: deleted elsewhere.
        case gone
        /// It didn't land, or nothing could tell (the read failed too): the screen goes back to the value the server
        /// last confirmed, with the error. Curating again is safe, since it sets a value rather than toggling one.
        case unconfirmed
    }

    /// After `setCurated` failed with `failure`: reads the record back when the failure may have hidden a success;
    /// any other failure is taken as it is.
    static func confirm(id: Int, _ isCurated: Bool, after failure: EnchiridionError?,
                        client: EnchiridionClient) async -> Outcome {
        guard failure?.mightHaveLanded == true else { return .unconfirmed }
        do {
            let stored = try await client.record(id: id).record
            return stored.isCurated == isCurated ? .landed(stored) : .unconfirmed
        } catch {
            return EnchiridionError.classify(error) == .notFound ? .gone : .unconfirmed
        }
    }
}

/// Deleting a record the way the web does: its media first (`DELETE /record/:id` drops the media rows but leaves the
/// files on voyager's disk), then the record. The media call always goes: what a list row or an open detail says
/// about media can be stale (added on the web since), and deleting none costs one request.
enum RecordDeletion {
    static func run(id: Int, client: EnchiridionClient) async throws {
        try await client.deleteMedia(recordID: id)
        try await client.delete(id: id)
    }
}
