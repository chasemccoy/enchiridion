import EnchiridionKit
import struct EnchiridionKit.Predicate
import Foundation
import Observation

/// The record at the other end of a link, as the detail's "Linked records" lists it.
public struct LinkedRecord: Identifiable, Hashable, Sendable {
    public var linkID: Int
    /// `.outgoing` when the shown record is the link's source.
    public var direction: LinkDirection
    /// The link's stored predicate; `direction` says which way it reads.
    public var predicate: Predicate
    /// The other end's id: what tapping opens.
    public var recordID: Int
    public var title: String?
    public var slug: String
    /// The source's content, sent for incoming links only: an untitled highlight shows it instead of a title.
    public var content: String?
    public var notes: String?

    public init(linkID: Int, direction: LinkDirection, predicate: Predicate, recordID: Int, title: String?,
                slug: String, content: String? = nil, notes: String? = nil) {
        self.linkID = linkID
        self.direction = direction
        self.predicate = predicate
        self.recordID = recordID
        self.title = title
        self.slug = slug
        self.content = content
        self.notes = notes
    }

    /// Unique within a record's links: a link from a record to itself is listed both ways under one link id.
    public var id: String { "\(direction == .outgoing ? "out" : "in")-\(linkID)" }

    /// The title, else the content (a highlight), else the slug.
    public var displayTitle: String {
        for text in [title, content] {
            if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return slug
    }
}

/// Linked records under one predicate as it reads from the shown record: "created by", "creator of", "tagged with".
public struct LinkGroup: Identifiable, Hashable, Sendable {
    /// The predicate's name as the vocabulary has it (lowercase): the group's key.
    public var name: String
    public var links: [LinkedRecord]

    public init(name: String, links: [LinkedRecord]) {
        self.name = name
        self.links = links
    }

    public var id: String { name }

    /// The label the group shows: `name` with its first letter capitalized ("Created by"), as the web's
    /// `capitalize(predicateName)` shows it.
    public var label: String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }
}

/// One record's detail: the record with its outgoing links, media and archive, every link touching it, and the
/// curate and delete actions.
@MainActor @Observable
public final class RecordDetailModel {
    /// The library's row for this record, as the list shows it: what a curate or an edit from the list, or a reloaded
    /// index, says about it. The screen reports it (`rowChanged(_:)`) so the detail can follow.
    public struct RowState: Equatable, Sendable {
        public var isCurated: Bool
        public var updatedAt: DBTimestamp
        /// A curate or delete from the list is in flight: the row hasn't settled.
        public var working: Bool

        public init(isCurated: Bool, updatedAt: DBTimestamp, working: Bool) {
            self.isCurated = isCurated
            self.updatedAt = updatedAt
            self.working = working
        }
    }

    public let id: Int

    /// The last load. What it loaded stays through a failed refresh: see `LoadState`.
    public private(set) var state: LoadState = .idle
    public private(set) var detail: RecordDetail?
    public private(set) var links: LinksBundle?
    /// `links` grouped for "Linked records": `linkGroups(_:)`.
    public private(set) var linkGroups: [LinkGroup] = []
    /// Records near this one by embedding and not linked to it yet (`GET /record/:id/similar`), most similar first.
    /// Empty until they load, and when they can't: suggestions never fail the detail. Ones linked since (here, or
    /// before the links loaded) are left out as they're read.
    public var similar: [SimilarRecord] {
        let linked = linkedIDs
        return suggestions.filter { !linked.contains($0.id) && $0.id != id }
    }
    private var suggestions: [SimilarRecord] = []
    /// A link being added or removed.
    public private(set) var isLinking = false
    /// A curate or delete in flight.
    public private(set) var isWorking = false
    /// Set once the record is gone (`delete()` succeeded, or it was found deleted elsewhere): the screen closes.
    public private(set) var isDeleted = false
    /// The last curate or delete that failed, for an alert; `clearActionError()` dismisses it.
    public private(set) var actionError: EnchiridionError?

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let client: EnchiridionClient
    @ObservationIgnored private let onChange: RecordChangeHandler?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var similarTask: Task<Void, Never>?
    /// Moves on every change made to the record here (a curate, an edit), so a load that was out meanwhile knows its
    /// answer may be older than what is shown.
    @ObservationIgnored private var changeGeneration = 0
    /// The last row state reported and not yet compared: kept while the row or this detail is busy, and compared once
    /// both have settled.
    @ObservationIgnored private var row: RowState?

    /// `onChange` hears every save and the delete (the library passes its `apply(_:)`).
    public init(id: Int, environment: AppEnvironment, onChange: RecordChangeHandler? = nil) {
        self.id = id
        self.environment = environment
        self.onChange = onChange
        client = environment.client(role: .app)
    }

    public var record: Record? { detail?.record }

    // MARK: Loading

    /// Loads the record and its links unless they're loaded. Joins a load in flight.
    public func load() async {
        if let loadTask { return await loadTask.value }
        guard state == .idle || state.error != nil else { return }
        await refresh()
    }

    /// Loads the record and its links again. Both or neither: a failure of either fails the load.
    public func refresh() async {
        await startLoad().value
    }

    /// The load in flight, or a new one. Once it's done, a row change that came in meanwhile is compared.
    @discardableResult
    private func startLoad() -> Task<Void, Never> {
        if let loadTask { return loadTask }
        let task = Task {
            await self.fetch()
            self.loadTask = nil
            self.syncWithRow()
        }
        loadTask = task
        return task
    }

    /// Waits until no load is out, including one a row change started, and the suggestions: tests.
    func settled() async {
        while let loadTask { await loadTask.value }
        await similarTask?.value
    }

    /// How many suggestions the detail shows.
    public nonisolated static let similarLimit = 6

    /// Loads the suggestions again, beside the record's own load (never holding it up).
    private func loadSimilar() {
        similarTask?.cancel()
        let client = client
        let id = id
        similarTask = Task { [weak self] in
            guard let found = try? await client.similar(id: id, limit: Self.similarLimit), !Task.isCancelled,
                  let self else { return }
            self.suggestions = found
        }
    }

    /// The records this one links to or from.
    private var linkedIDs: Set<Int> {
        Set(linkGroups.flatMap(\.links).map(\.recordID))
    }

    /// The library's row for this record changed (nil: it isn't listed now). Once the row has settled and says
    /// something newer than the record shown (`rowIsAhead`), the detail reloads: a curate from the list, say, that
    /// landed after this detail's load was answered. While this detail is loading or curating, or the row is, the
    /// comparison waits until both are done, so a change is never missed for having come at a busy moment.
    public func rowChanged(_ row: RowState?) {
        self.row = row
        syncWithRow()
    }

    private func syncWithRow() {
        guard let row, !row.working, !isWorking, !isDeleted, loadTask == nil, let record else { return }
        self.row = nil
        if Self.rowIsAhead(row, of: record) { startLoad() }
    }

    /// A record changed here while the load was out (a curate, an edit) is kept over the loaded one unless the loaded
    /// one is newer: the server may have answered from before the change. A load answered 404 found the record deleted
    /// elsewhere (ids are never reused, so Retry can't bring it back): it's reported `.vanished`, as a curate's 404 is,
    /// so the row leaves, this screen closes and the library says so.
    private func fetch() async {
        state = .loading
        loadSimilar()
        let generation = changeGeneration
        do {
            async let detail = client.record(id: id)
            async let links = client.links(id: id)
            let (fetchedDetail, loadedLinks) = try await (detail, links)
            var loadedDetail = fetchedDetail
            if generation != changeGeneration, let shown = self.detail?.record, shown.id == loadedDetail.record.id,
               shown.recordUpdatedAt >= loadedDetail.record.recordUpdatedAt {
                loadedDetail.record = shown
            }
            self.detail = loadedDetail
            self.links = loadedLinks
            linkGroups = Self.linkGroups(loadedLinks)
            state = .loaded
        } catch {
            guard let error = EnchiridionError.classify(error) else {
                state = detail == nil ? .idle : .loaded
                return
            }
            state = .failed(error)
            if error == .notFound, !isDeleted { apply(.vanished(id: id)) }
        }
    }

    // MARK: Actions

    /// Curates or uncurates the record: the switch moves at once, then the server is sent `{id, slug, isCurated}`.
    /// A failure moves it back and sets `actionError`, unless its answer was lost and the record, read back, holds the
    /// new value (`RecordCuration.confirm`): then it landed. A record deleted elsewhere (`.notFound`) is reported
    /// `.vanished`: this screen closes, so the library, which stays, is the one to say so.
    @discardableResult
    public func setCurated(_ isCurated: Bool) async -> Bool {
        guard let current = detail?.record, !isWorking else { return false }
        guard current.isCurated != isCurated else { return true }
        detail?.record.isCurated = isCurated
        changeGeneration += 1
        isWorking = true
        defer {
            isWorking = false
            syncWithRow()
        }
        do {
            let saved = try await client.setCurated(id: id, slug: current.slug, isCurated)
            apply(.updated(saved))
            return true
        } catch {
            var failure = EnchiridionError.classify(error)
            switch await RecordCuration.confirm(id: id, isCurated, after: failure, client: client) {
            case .landed(let stored):
                apply(.updated(stored))
                return true
            case .gone:
                failure = .notFound
            case .unconfirmed:
                break
            }
            if failure == .notFound {
                apply(.vanished(id: id))
                return false
            }
            if detail?.record.isCurated == isCurated {
                detail?.record.isCurated = current.isCurated
                changeGeneration += 1
            }
            if let failure { actionError = failure }
            return false
        }
    }

    /// Deletes the record: its media first (so the files go to voyager's Trash, as the web does; `RecordDeletion`),
    /// then the record. Sets `isDeleted`, or `actionError` on failure.
    @discardableResult
    public func delete() async -> Bool {
        guard !isWorking, !isDeleted else { return isDeleted }
        isWorking = true
        defer { isWorking = false }
        do {
            try await RecordDeletion.run(id: id, client: client)
            isDeleted = true
            onChange?(.deleted(id: id))
            return true
        } catch {
            if let error = EnchiridionError.classify(error) { actionError = error }
            return false
        }
    }

    /// A search for "Add link": this record and the ones it's linked with left out.
    public func makeLinkSearch() -> RecordSearchModel {
        let search = RecordSearchModel(environment: environment)
        search.excludedIDs = linkedIDs.union([id])
        return search
    }

    /// Links this record to `target` (`PUT /link`, which stores the canonical direction), then reloads its links (so a
    /// suggestion it was leaves the suggestions). A failure sets `actionError`.
    @discardableResult
    public func addLink(to target: Int, predicate: Predicate) async -> Bool {
        guard !isLinking, !isDeleted else { return false }
        isLinking = true
        defer { isLinking = false }
        do {
            _ = try await client.putLink(LinkInput(sourceId: id, targetId: target, predicate: predicate))
            await reloadLinks()
            return true
        } catch {
            if let error = EnchiridionError.classify(error) { actionError = error }
            return false
        }
    }

    /// Removes a link (`DELETE /link/:id`), then reloads the links. A failure sets `actionError`.
    @discardableResult
    public func removeLink(_ linked: LinkedRecord) async -> Bool {
        guard !isLinking, !isDeleted else { return false }
        isLinking = true
        defer { isLinking = false }
        do {
            try await client.deleteLink(id: linked.linkID)
            await reloadLinks()
            return true
        } catch {
            if let error = EnchiridionError.classify(error) { actionError = error }
            return false
        }
    }

    /// The links alone, after this screen changed them. A failure keeps the ones shown less the change: the next
    /// refresh brings them right.
    private func reloadLinks() async {
        guard let loaded = try? await client.links(id: id) else { return }
        links = loaded
        linkGroups = Self.linkGroups(loaded)
    }

    public func clearActionError() {
        actionError = nil
    }

    /// An editor for the loaded record whose save updates this detail and, through it, whoever listens; nil until the
    /// record has loaded. The editor can outlive this detail (a reload moved the selection while it was open): its
    /// changes then go straight to whoever this detail reported to, so the rows still hear them.
    public func makeEditor() -> RecordEditorModel? {
        guard let record else { return nil }
        let onChange = onChange
        return RecordEditorModel(draft: RecordDraft(record), environment: environment) { [weak self] change in
            if let self {
                self.apply(change)
            } else {
                onChange?(change)
            }
        }
    }

    /// Takes a change to this record (from its editor) and passes every change on.
    public func apply(_ change: RecordChange) {
        switch change {
        case .updated(let record) where record.id == id:
            detail?.record = record
            changeGeneration += 1
        case .deleted(let deleted) where deleted == id, .vanished(let deleted) where deleted == id:
            isDeleted = true
        default:
            break
        }
        onChange?(change)
    }

    // MARK: Pure parts

    /// Whether a list row says something newer than `record`: a later update, or the same one with the other curation
    /// (two writes in one second share a timestamp). A row behind the detail (this detail's own curate, not merged into
    /// the row yet) never reloads it.
    public nonisolated static func rowIsAhead(_ row: RowState, of record: Record) -> Bool {
        row.updatedAt > record.recordUpdatedAt
            || (row.updatedAt == record.recordUpdatedAt && row.isCurated != record.isCurated)
    }

    /// Every link, grouped by its predicate as read from this record (outgoing by the predicate's name, incoming by
    /// its inverse's), groups in order of first appearance with the outgoing links first, each in the server's order.
    /// Containment links are included, unlike the web's link list, which shows them elsewhere.
    public nonisolated static func linkGroups(_ bundle: LinksBundle) -> [LinkGroup] {
        let outgoing = bundle.outgoingLinks.map { link in
            LinkedRecord(linkID: link.id, direction: .outgoing, predicate: link.predicate, recordID: link.targetId,
                         title: link.target.title, slug: link.target.slug, notes: link.notes)
        }
        let incoming = bundle.incomingLinks.map { link in
            LinkedRecord(linkID: link.id, direction: .incoming, predicate: link.predicate, recordID: link.sourceId,
                         title: link.source.title, slug: link.source.slug, content: link.source.content,
                         notes: link.notes)
        }
        var order: [String] = []
        var groups: [String: [LinkedRecord]] = [:]
        for linked in outgoing + incoming {
            let name = linked.predicate.displayName(linked.direction)
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(linked)
        }
        return order.map { LinkGroup(name: $0, links: groups[$0] ?? []) }
    }
}
