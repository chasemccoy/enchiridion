import EnchiridionKit
import Foundation
import Observation

/// A run of list rows under one month header ("September 2026"), or the whole flat list while searching.
public struct RecordSection: Identifiable, Equatable, Sendable {
    /// The title, or a fixed id for the untitled flat section.
    public let id: String
    /// "September 2026" in the device's time zone; nil for the flat list (searching), whose header is hidden.
    public let title: String?
    public let records: [ListRecord]

    public init(id: String, title: String?, records: [ListRecord]) {
        self.id = id
        self.title = title
        self.records = records
    }

    /// "(12)": the web shows a group's size only past four records.
    public var countText: String? { records.count > 4 ? "(\(records.count))" : nil }

    /// "September 2026 (12)", or just "September 2026" for four records or fewer; nil for the flat list.
    public var heading: String? {
        guard let title else { return nil }
        return countText.map { "\(title) \($0)" } ?? title
    }
}

/// The library: every record at once (as the web's index loads them), narrowed by type and curation, searched with
/// hybrid search, grouped by month, and the one selected.
@MainActor @Observable
public final class LibraryModel {
    /// The web index's toolbar filters.
    public struct Filters: Hashable, Sendable {
        /// Only records of this type; nil for all.
        public var type: RecordType?
        /// Hide curated records.
        public var needsCuration: Bool
        /// Only records with media attached (the web's "Media" checkbox: any media, not only images).
        public var hasMedia: Bool
        /// The order chosen; nil for the default (`Sort.default(searching:)`).
        public var sort: Sort?

        public init(type: RecordType? = nil, needsCuration: Bool = false, hasMedia: Bool = false, sort: Sort? = nil) {
            self.type = type
            self.needsCuration = needsCuration
            self.hasMedia = hasMedia
            self.sort = sort
        }

        /// Whether anything hides rows. The order isn't a filter: it never hides anything.
        public var isActive: Bool { type != nil || needsCuration || hasMedia }

        public func admits(_ record: ListRecord) -> Bool {
            if let type, record.type != type { return false }
            if needsCuration, record.isCurated { return false }
            if hasMedia, record.media.isEmpty { return false }
            return true
        }

        /// The order in effect: the chosen one, else the default; relevance only while searching (the web's rule).
        public func effectiveSort(searching: Bool) -> Sort {
            guard let sort, searching || sort != .relevance else { return .default(searching: searching) }
            return sort
        }
    }

    /// The web index's sort menu.
    public enum Sort: String, CaseIterable, Hashable, Sendable {
        /// The search's own ranking; only while searching.
        case relevance
        case newest
        case oldest
        /// Title A–Z; untitled records last.
        case title

        public static func `default`(searching: Bool) -> Sort { searching ? .relevance : .newest }

        /// The orders offered: relevance only while searching.
        public static func options(searching: Bool) -> [Sort] {
            searching ? allCases : allCases.filter { $0 != .relevance }
        }

        public var title: String {
            switch self {
            case .relevance: "Relevance"
            case .newest: "Newest"
            case .oldest: "Oldest"
            case .title: "Title A–Z"
            }
        }
    }

    /// As many hybrid search results as the web asks for.
    public nonisolated static let searchLimit = 100

    public let environment: AppEnvironment

    /// The index's last load. Rows stay through a failed refresh: see `LoadState`.
    public private(set) var state: LoadState = .idle
    /// The whole index, newest first, as `POST /records` returned it, with the changes made here since merged in
    /// (including those made while it loaded: `replay(_:onto:)`).
    public private(set) var records: [ListRecord] = []
    /// The last search's results in relevance order, kept while a refined query loads (as the web keeps its previous
    /// results); nil when no search has answered since the field was last cleared.
    public private(set) var searchResults: [ListRecord]?
    public private(set) var searchState: LoadState = .idle
    /// The query the list shows results for: `query` trimmed, once its debounce has passed. "" while browsing.
    public private(set) var activeQuery = ""
    /// What the list shows: the index or the search results, through `filters`.
    public private(set) var visibleRecords: [ListRecord] = []
    /// `visibleRecords` by local month of `recordCreatedAt` while browsing; one untitled section while searching.
    public private(set) var sections: [RecordSection] = []
    /// Rows with a curate or delete in flight.
    public private(set) var workingIDs: Set<Int> = []
    /// The last curate or delete that failed, for an alert; `clearActionError()` dismisses it.
    public private(set) var actionError: EnchiridionError?

    public var filters = Filters() {
        didSet { if filters != oldValue { rebuild() } }
    }

    /// The search field. Non-blank text searches after `Timings.searchDebounce`; clearing it shows the index at once.
    public var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }

    /// The record the detail column shows. When it leaves `visibleRecords` the record that took its place is selected
    /// instead (`successor(of:previous:next:)`), unless the list became a different list (search started, cleared or
    /// changed): then a position in the old one means nothing, and the selection stays.
    public var selectedID: Int?

    @ObservationIgnored private let client: EnchiridionClient
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?
    /// The text `searchTask` is debouncing or fetching.
    @ObservationIgnored private var searchTaskQuery: String?
    /// The query `searchResults` answer.
    @ObservationIgnored private var resultsQuery: String?
    /// Whether `POST /records` is out. Its answer may have been made before a change confirmed here meanwhile, so
    /// those changes are kept in `changesDuringLoad` and replayed onto it.
    @ObservationIgnored private var fetchingIndex = false
    @ObservationIgnored private var changesDuringLoad: [RecordChange] = []
    /// How many searches are out. A search's answer may also predate a change confirmed meanwhile, so changes are
    /// logged in `changesDuringSearches` while any is; each search replays the ones made after it started. The log
    /// empties once none is out, so the positions searches hold stay valid.
    @ObservationIgnored private var searchesOut = 0
    @ObservationIgnored private var changesDuringSearches: [RecordChange] = []
    /// Curations sent and not yet answered, by id: the rows keep showing them whatever a load brings meanwhile.
    @ObservationIgnored private var pendingCurations: [Int: Bool] = [:]

    public init(environment: AppEnvironment) {
        self.environment = environment
        client = environment.client(role: .app)
    }

    /// Whether the list shows search results rather than the index.
    public var isSearching: Bool { !activeQuery.isEmpty }

    /// The toolbar's count, in the web's words: "567 records", "12 of 567 records", "8 results", "Searching…",
    /// "Search failed. Try again."; nil while no index has loaded (loading, failed, not on the list), when there is
    /// nothing to count yet.
    public var countText: String? {
        if isSearching {
            if searchState.error != nil { return "Search failed. Try again." }
            if searchState.isLoading, visibleRecords.isEmpty { return "Searching…" }
        } else if records.isEmpty, state != .loaded {
            return nil
        }
        let shown = visibleRecords.count
        let total = (isSearching ? searchResults ?? [] : records).count
        let noun = isSearching ? (total == 1 ? "result" : "results") : (total == 1 ? "record" : "records")
        return shown == total ? "\(shown) \(noun)" : "\(shown) of \(total) \(noun)"
    }

    /// The row for `id`, from the index or the search results.
    public func row(id: Int) -> ListRecord? {
        records.first { $0.id == id } ?? searchResults?.first { $0.id == id }
    }

    // MARK: Loading

    /// Loads the index unless it already has (a view's `.task` calls this on every appearance). Joins a load already
    /// in flight.
    public func load() async {
        if let loadTask { return await loadTask.value }
        guard state == .idle || state.error != nil else { return }
        await reload()
    }

    /// Loads the index again (pull to refresh), and, while searching, searches again without waiting for a debounce:
    /// for what the field holds now, which may be newer than the results shown (typed while the index loaded).
    public func refresh() async {
        if let loadTask {
            await loadTask.value
        } else {
            await reload()
        }
        let query = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearching, !query.isEmpty else { return }
        cancelSearch()
        let task = Task { await self.search(query) }
        searchTask = task
        searchTaskQuery = query
        await task.value
    }

    /// Reloads the index when it lacks the newest record: one small request, for coming back to the app after a
    /// share or a save elsewhere. Nothing while a load is out or before the index has loaded.
    public func refreshIfNewer() async {
        guard loadTask == nil, state == .loaded else { return }
        guard let newest = try? await client.list(.newest).first,
              loadTask == nil, !records.contains(where: { $0.id == newest.id })
        else { return }
        await refresh()
    }

    private func reload() async {
        let task = Task {
            await self.fetchIndex()
            self.loadTask = nil
        }
        loadTask = task
        await task.value
    }

    private func fetchIndex() async {
        state = .loading
        fetchingIndex = true
        changesDuringLoad = []
        defer {
            fetchingIndex = false
            changesDuringLoad = []
        }
        do {
            let fetched = try await client.list(.index)
            records = withPendingCurations(Self.replay(changesDuringLoad, onto: fetched))
            state = .loaded
            rebuild()
        } catch {
            guard let error = EnchiridionError.classify(error) else {
                state = records.isEmpty ? .idle : .loaded
                return
            }
            state = .failed(error)
        }
    }

    // MARK: Search

    private func queryChanged() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            cancelSearch()
            guard isSearching || searchResults != nil || searchState != .idle else { return }
            activeQuery = ""
            searchResults = nil
            resultsQuery = nil
            searchState = .idle
            rebuild(sourceChanged: true)
            return
        }
        // Already waiting on or fetching this text (a space typed after it): let that finish.
        guard trimmed != searchTaskQuery else { return }
        cancelSearch()
        // Back to what's showing (a letter typed and deleted before its debounce passed): nothing to ask.
        guard trimmed != activeQuery || searchState != .loaded else { return }
        let environment = environment
        searchTaskQuery = trimmed
        searchTask = Task { [weak self] in
            do {
                try await environment.sleep(for: environment.timings.searchDebounce)
            } catch {
                return
            }
            await self?.search(trimmed)
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchTaskQuery = nil
    }

    /// Shows the results for `query`, keeping the previous results on screen until they arrive. A superseded search
    /// (cancelled, or the field moved on) changes nothing. Starting one from the index closes the open record, as the
    /// web's search does; results for another query are another list, so the selection stays (the successor rule
    /// applies only when the same query's results change). Changes confirmed while it was out are replayed onto its
    /// answer, as onto the index's: a record deleted meanwhile stays gone, a curate stays.
    private func search(_ query: String) async {
        if searchResults == nil { selectedID = nil }
        activeQuery = query
        searchState = .loading
        rebuild(sourceChanged: true)
        let firstChange = changesDuringSearches.count
        searchesOut += 1
        defer {
            searchesOut -= 1
            if searchesOut == 0 { changesDuringSearches = [] }
            if searchTaskQuery == query, !Task.isCancelled { searchTaskQuery = nil }
        }
        do {
            let rows = try await client.search(query, limit: Self.searchLimit)
            guard !Task.isCancelled, activeQuery == query else { return }
            let sameQuery = resultsQuery == query
            let changes = Array(changesDuringSearches[firstChange...])
            searchResults = withPendingCurations(Self.replay(changes, onto: rows, inserting: false))
            resultsQuery = query
            searchState = .loaded
            rebuild(sourceChanged: !sameQuery)
        } catch {
            guard !Task.isCancelled, activeQuery == query, let error = EnchiridionError.classify(error) else { return }
            searchState = .failed(error)
        }
    }

    /// Waits for a load and a pending search to finish: tests.
    func settled() async {
        await loadTask?.value
        await searchTask?.value
    }

    // MARK: Changes

    /// Folds a record the server returned into the rows: a listed one takes the record's columns and keeps its media,
    /// links and score; one the index doesn't list (just created) is inserted in index order.
    public func apply(saved record: Record) {
        noteChange(.created(record))
        if !merge(record) {
            let row = ListRecord(record)
            let index = records.firstIndex { Self.precedes(row, $0) } ?? records.endIndex
            records.insert(row, at: index)
        }
        rebuild()
    }

    /// Applies what a detail or editor model did. An update to a record the index doesn't list (an untitled highlight
    /// opened from its parent) is not inserted: the index hides those. A record a detail found deleted elsewhere
    /// (`.vanished`) leaves, and `actionError` says so: the detail that found it closes, taking its own alert with it.
    public func apply(_ change: RecordChange) {
        switch change {
        case .created(let record):
            apply(saved: record)
        case .updated(let record):
            noteChange(change)
            if merge(record) { rebuild() }
        case .deleted(let id):
            remove(id: id)
        case .vanished(let id):
            remove(id: id)
            actionError = .notFound
        }
    }

    /// Drops the record from the rows (it was deleted). A selection on it moves to its successor, or clears.
    public func remove(id: Int) {
        noteChange(.deleted(id: id))
        records.removeAll { $0.id == id }
        searchResults?.removeAll { $0.id == id }
        rebuild()
        if selectedID == id { selectedID = nil }
    }

    /// Curates or uncurates a row: at once on screen (so it leaves a needs-curation list right away), then on the
    /// server, which is sent only `{id, slug, isCurated}`. A failure puts it back and sets `actionError`; a record
    /// deleted elsewhere (`.notFound`) leaves the rows. A lost answer may hide a curate that landed, so the record is
    /// read back first (`RecordCuration.confirm`): holding the new value, it's a success. Nothing happens to a row with
    /// a curate or delete in flight.
    @discardableResult
    public func setCurated(id: Int, _ isCurated: Bool) async -> Bool {
        guard let current = row(id: id), !workingIDs.contains(id) else { return false }
        guard current.isCurated != isCurated else { return true }
        update(id) { $0.isCurated = isCurated }
        rebuild()
        workingIDs.insert(id)
        pendingCurations[id] = isCurated
        defer { workingIDs.remove(id) }
        do {
            let saved = try await client.setCurated(id: id, slug: current.slug, isCurated)
            pendingCurations[id] = nil
            apply(.updated(saved))
            return true
        } catch {
            var failure = EnchiridionError.classify(error)
            switch await RecordCuration.confirm(id: id, isCurated, after: failure, client: client) {
            case .landed(let stored):
                pendingCurations[id] = nil
                apply(.updated(stored))
                return true
            case .gone:
                failure = .notFound
            case .unconfirmed:
                break
            }
            pendingCurations[id] = nil
            if failure == .notFound {
                remove(id: id)
            } else if row(id: id)?.isCurated == isCurated {
                // Put it back unless something newer (a load, another toggle) already changed it.
                update(id) { $0.isCurated = current.isCurated }
                rebuild()
            }
            if let failure { actionError = failure }
            return false
        }
    }

    /// Deletes a record on the server (its media first, `RecordDeletion`), then drops its row. A failure sets
    /// `actionError` and keeps the row.
    @discardableResult
    public func delete(id: Int) async -> Bool {
        guard !workingIDs.contains(id) else { return false }
        workingIDs.insert(id)
        defer { workingIDs.remove(id) }
        do {
            try await RecordDeletion.run(id: id, client: client)
            remove(id: id)
            return true
        } catch {
            if let error = EnchiridionError.classify(error) { actionError = error }
            return false
        }
    }

    public func clearActionError() {
        actionError = nil
    }

    // MARK: Other models

    /// The detail model for a record, reporting its changes back to these rows.
    public func detailModel(id: Int) -> RecordDetailModel {
        RecordDetailModel(id: id, environment: environment) { [weak self] change in self?.apply(change) }
    }

    /// An editor for a new record, which lands in these rows once saved.
    public func newRecordEditor(_ draft: RecordDraft = RecordDraft()) -> RecordEditorModel {
        RecordEditorModel(draft: draft, environment: environment) { [weak self] change in self?.apply(change) }
    }

    /// An editor for a listed record (a context menu's Edit); a detail screen uses its own `makeEditor()`.
    public func editor(for row: ListRecord) -> RecordEditorModel {
        RecordEditorModel(draft: RecordDraft(row), environment: environment) { [weak self] change in
            self?.apply(change)
        }
    }

    // MARK: Derived state

    /// Recomputes what the list shows. `sourceChanged`: the list became another list (the index for results, or one
    /// query's results for another's), so the successor rule doesn't apply.
    private func rebuild(sourceChanged: Bool = false) {
        let base = isSearching ? searchResults ?? [] : records
        let next = Self.visible(base, filters: filters, searching: isSearching)
        let previousIDs = visibleRecords.map(\.id)
        visibleRecords = next
        // Months only while browsing in date order, as the web groups.
        let grouped = !isSearching && filters.effectiveSort(searching: false) != .title
        sections = Self.sections(next, grouped: grouped, timeZone: environment.timeZone)
        guard !sourceChanged else { return }
        let successor = Self.successor(of: selectedID, previous: previousIDs, next: next.map(\.id))
        if successor != selectedID { selectedID = successor }
    }

    /// Keeps a confirmed change for the index load and the searches in flight, if any, to replay onto their answers.
    private func noteChange(_ change: RecordChange) {
        if fetchingIndex { changesDuringLoad.append(change) }
        if searchesOut > 0 { changesDuringSearches.append(change) }
    }

    /// `rows` showing the curations still waiting for their answers, whatever a load says.
    private func withPendingCurations(_ rows: [ListRecord]) -> [ListRecord] {
        guard !pendingCurations.isEmpty else { return rows }
        return rows.map { row in
            guard let isCurated = pendingCurations[row.id] else { return row }
            var row = row
            row.isCurated = isCurated
            return row
        }
    }

    /// Merges `record` into every row with its id; false when there was none.
    @discardableResult
    private func merge(_ record: Record) -> Bool {
        var found = false
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index].merge(record)
            found = true
        }
        if let index = searchResults?.firstIndex(where: { $0.id == record.id }) {
            searchResults?[index].merge(record)
            found = true
        }
        return found
    }

    private func update(_ id: Int, _ change: (inout ListRecord) -> Void) {
        if let index = records.firstIndex(where: { $0.id == id }) { change(&records[index]) }
        if let index = searchResults?.firstIndex(where: { $0.id == id }) { change(&searchResults![index]) }
    }

    // MARK: Pure parts

    /// The rows `filters` admits, in the order it asks for (the web's IndexView filter and sort). Newest while
    /// browsing and relevance while searching keep the order the rows came in (the index arrives newest first); the
    /// others sort, ties keeping that order.
    public nonisolated static func visible(_ records: [ListRecord], filters: Filters,
                                           searching: Bool = false) -> [ListRecord] {
        let admitted = filters.isActive ? records.filter(filters.admits) : records
        let created: (ListRecord) -> String = { $0.recordCreatedAt.raw }
        switch filters.effectiveSort(searching: searching) {
        case .relevance:
            return admitted
        case .newest:
            return searching ? stableSorted(admitted) { created($0) > created($1) } : admitted
        case .oldest:
            return stableSorted(admitted) { created($0) < created($1) }
        case .title:
            return stableSorted(admitted) { a, b in
                switch (Self.sortTitle(a), Self.sortTitle(b)) {
                case let (a?, b?): a.localizedStandardCompare(b) == .orderedAscending
                case (.some, nil): true
                default: false
                }
            }
        }
    }

    /// A row's title for sorting; nil when it has none, so untitled rows go last.
    private nonisolated static func sortTitle(_ row: ListRecord) -> String? {
        guard let title = row.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return title
    }

    /// `rows` sorted by `isBefore`, rows it doesn't order keeping their order.
    private nonisolated static func stableSorted(_ rows: [ListRecord],
                                                 by isBefore: (ListRecord, ListRecord) -> Bool) -> [ListRecord] {
        rows.enumerated().sorted { a, b in
            if isBefore(a.element, b.element) { return true }
            if isBefore(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Rows grouped by the local month of `recordCreatedAt` ("September 2026"), each group where its first row falls
    /// and in row order (the web's SplitViewLayout); rows whose timestamp doesn't parse go last, under "Undated".
    /// Ungrouped, one untitled section. No rows, no sections.
    public nonisolated static func sections(_ records: [ListRecord], grouped: Bool,
                                            timeZone: TimeZone) -> [RecordSection] {
        guard !records.isEmpty else { return [] }
        guard grouped else { return [RecordSection(id: flatSectionID, title: nil, records: records)] }
        var order: [String] = []
        var groups: [String: [ListRecord]] = [:]
        var undated: [ListRecord] = []
        for record in records {
            guard let date = record.recordCreatedAt.date else {
                undated.append(record)
                continue
            }
            let title = DBTimestamp.Style.month.format(date, timeZone: timeZone)
            if groups[title] == nil { order.append(title) }
            groups[title, default: []].append(record)
        }
        var sections = order.map { RecordSection(id: $0, title: $0, records: groups[$0] ?? []) }
        if !undated.isEmpty { sections.append(RecordSection(id: undatedTitle, title: undatedTitle, records: undated)) }
        return sections
    }

    nonisolated static let flatSectionID = "all"
    nonisolated static let undatedTitle = "Undated"

    /// The selection after the visible rows change from `previous` to `next` (the web's fix): a selection still
    /// listed stays; one that left the list moves to the record that took its index, else the last record, else
    /// none; one that was never listed (opened from a link) is left alone.
    public nonisolated static func successor(of selected: Int?, previous: [Int], next: [Int]) -> Int? {
        guard let selected, !next.contains(selected), let index = previous.firstIndex(of: selected) else {
            return selected
        }
        guard !next.isEmpty else { return nil }
        return next[min(index, next.count - 1)]
    }

    /// The index's order: newest `recordCreatedAt` first, then slug.
    nonisolated static func precedes(_ lhs: ListRecord, _ rhs: ListRecord) -> Bool {
        lhs.recordCreatedAt == rhs.recordCreatedAt ? lhs.slug < rhs.slug : lhs.recordCreatedAt > rhs.recordCreatedAt
    }

    /// `rows` (an index or search results the server may have made before these changes) with `changes` (confirmed
    /// here while it loaded) applied in order: a deleted record leaves; an updated one is merged unless the row is
    /// newer; a created one is merged, or, when `inserting` and the rows don't have it yet, inserted in index order.
    /// Search results are in relevance order, so a search's answer doesn't take new records (`inserting: false`).
    public nonisolated static func replay(_ changes: [RecordChange], onto rows: [ListRecord],
                                          inserting: Bool = true) -> [ListRecord] {
        var rows = rows
        for change in changes {
            switch change {
            case .deleted(let id), .vanished(let id):
                rows.removeAll { $0.id == id }
            case .updated(let record), .created(let record):
                if let index = rows.firstIndex(where: { $0.id == record.id }) {
                    if rows[index].recordUpdatedAt <= record.recordUpdatedAt { rows[index].merge(record) }
                } else if inserting, case .created = change {
                    let row = ListRecord(record)
                    rows.insert(row, at: rows.firstIndex { precedes(row, $0) } ?? rows.endIndex)
                }
            }
        }
        return rows
    }
}
