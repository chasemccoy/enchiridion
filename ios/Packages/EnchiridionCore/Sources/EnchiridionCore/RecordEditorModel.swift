import EnchiridionKit
import Foundation
import Observation

/// The editor's fields: a new record, or an existing one's editable columns.
///
/// Text fields are plain strings (empty for none). A create sends every field; an edit sends only the fields that
/// differ from the draft the editor opened with (`update(from:)`), an emptied one as `null` so it clears. Title and URL
/// are trimmed, while summary, content and notes keep their text as typed (only blank becomes `null`).
public struct RecordDraft: Hashable, Sendable {
    /// nil for a new record.
    public let id: Int?
    /// The existing record's slug, which every update must resend; nil for a new record (one is made on save).
    public let slug: String?
    /// Kept as it was: `manual` for new records.
    public let source: RecordSource?
    public var type: RecordType
    public var title: String
    public var url: String
    public var summary: String
    public var content: String
    public var notes: String
    public var isCurated: Bool

    /// A new record.
    public init(type: RecordType = .artifact, title: String = "", url: String = "", summary: String = "",
                content: String = "", notes: String = "", isCurated: Bool = false) {
        id = nil
        slug = nil
        source = .manual
        self.type = type
        self.title = title
        self.url = url
        self.summary = summary
        self.content = content
        self.notes = notes
        self.isCurated = isCurated
    }

    /// An existing record's fields.
    public init(_ record: Record) {
        id = record.id
        slug = record.slug
        source = record.source
        type = record.type
        title = record.title ?? ""
        url = record.url ?? ""
        summary = record.summary ?? ""
        content = record.content ?? ""
        notes = record.notes ?? ""
        isCurated = record.isCurated
    }

    /// A list row's fields: the same editable columns as the record's.
    public init(_ row: ListRecord) {
        id = row.id
        slug = row.slug
        source = row.source
        type = row.type
        title = row.title ?? ""
        url = row.url ?? ""
        summary = row.summary ?? ""
        content = row.content ?? ""
        notes = row.notes ?? ""
        isCurated = row.isCurated
    }

    public var isNew: Bool { id == nil }

    /// Something worth saving: a title, URL, summary or content that isn't blank.
    public var hasContent: Bool {
        [title, url, summary, content].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The slug a new record would like: from the title, else the URL; "" means a fallback (`RecordSlug.base`).
    public var slugBase: String {
        RecordSlug.base(title: Self.line(title), url: Self.line(url))
    }

    /// The `PUT /record` body under `slug` (an update's must be its own `slug`), with every field.
    public func input(slug: String) -> RecordInput {
        RecordInput(id: id, slug: slug, type: type, title: Self.line(title), url: Self.line(url),
                    isCurated: isCurated, summary: Self.text(summary), content: Self.text(content),
                    notes: Self.text(notes), source: source)
    }

    /// An existing record's `PUT /record` update: its id and slug, and only the fields that differ from `initial` (the
    /// draft as the editor opened). The editor may have opened on a copy loaded long ago (a list row, an open detail),
    /// and the server writes every key it gets, so a field the user didn't touch is never sent: a change made
    /// elsewhere since stays. nil for a new record.
    public func update(from initial: RecordDraft) -> RecordInput? {
        guard let id, let slug else { return nil }
        let input = input(slug: slug)
        var base = initial.input(slug: slug)
        base.id = id
        return input.only(input.fieldsDiffering(from: base))
    }

    /// A one-line field: trimmed, nil when empty.
    static func line(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A multi-line field: as typed, nil when blank.
    static func text(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}

/// Creates or edits one record.
///
/// A create makes its slug the way the web does (`Slug.make(title)`), else from the URL's host and path, else a
/// fallback, and makes it unique by asking for `base`, `base-2` … (`RecordSlug`). A create whose answer was lost is
/// recognized on the next attempt instead of saved twice (`RecordCreation`), and looked up when the editor closes
/// without one, so the rows show it if it landed (`close()`). An edit resends the record's own slug and
/// only the fields the user changed; one with nothing changed just reads the record back. An edit of a record deleted
/// elsewhere fails with `.notFound`, which the editor shows with the typed text still there; it reports `.deleted`, so
/// the rows drop it and an open detail closes, only when it closes (`close()`): reporting it at once would close the
/// detail that presents this editor, error and text with it.
///
/// An update that failed may have landed all the same (its answer lost), so its fields are sent again by every later
/// save, even a field the user has since put back to how the editor opened (`hasUnsettledEdit`); a lost answer is
/// checked by reading the record back first. A save has `Timings.editorDeadline` in all; past it it is cancelled and
/// fails as unreachable, so the sheet never holds "Saving" with no way out.
@MainActor @Observable
public final class RecordEditorModel {
    public var draft: RecordDraft
    /// The draft as the editor opened, for "discard changes?".
    public let initial: RecordDraft
    public private(set) var state: SaveState = .editing
    /// A new record's links, added once it's saved (an edit's links are changed on the detail, one at a time).
    public var links: [PendingLink] = []
    /// Links that couldn't be added after the create: the sheet says so, and `retryLinks()` adds just these.
    public private(set) var failedLinks: [PendingLink] = []
    /// The link picker's search.
    @ObservationIgnored public let linkSearch: RecordSearchModel
    /// The fields of an update that failed and may have landed: every later save sends them again, whatever the draft
    /// holds, and the sheet treats them as changes until one lands.
    private var attempted: Set<RecordInput.Field> = []
    /// A create's last save failed, but the record may exist all the same (`RecordCreation.isUnconfirmed`).
    private var createUnconfirmed = false

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let client: EnchiridionClient
    @ObservationIgnored private let onChange: RecordChangeHandler?
    @ObservationIgnored private let creation: RecordCreation
    /// The record an edit found deleted elsewhere, reported when the editor closes.
    @ObservationIgnored private var vanished: Int?

    /// `onChange` hears `.created` or `.updated` once the save lands.
    public init(draft: RecordDraft = RecordDraft(), environment: AppEnvironment,
                onChange: RecordChangeHandler? = nil) {
        self.draft = draft
        initial = draft
        self.environment = environment
        self.onChange = onChange
        client = environment.client(role: .app)
        creation = RecordCreation(client: client, fallback: environment.fallbackSlug)
        linkSearch = RecordSearchModel(environment: environment)
    }

    public var isNew: Bool { draft.isNew }
    public var hasChanges: Bool { draft != initial || !links.isEmpty }
    /// An edit's update failed in a way that may have landed: the server may hold something the draft no longer does,
    /// so Save stays on and closing asks first, even with no change left in the draft.
    public var hasUnsettledEdit: Bool { !attempted.isEmpty }
    /// The last save failed, but what it sent may have reached the server: a create whose record may exist, or an edit
    /// with an unsettled update. The sheet says it couldn't confirm the save rather than that it failed; saving again
    /// never saves twice (a create looks its record up first, an update is sent again).
    public var mayHaveSaved: Bool { isNew ? createUnconfirmed : hasUnsettledEdit }
    public var canSave: Bool { draft.hasContent && !state.isSaving }

    /// Why Save is off, in words; nil when the draft can be saved.
    public var validationMessage: String? {
        draft.hasContent ? nil : "Add a title, URL, summary or content to save."
    }

    /// Saves the draft; the stored record, or nil when it failed (`state` says why) or there was nothing to save.
    ///
    /// The save races `Timings.editorDeadline`. When the deadline wins, the save is cancelled (URLSession stops its
    /// request) and awaited, so a create or update that may have landed is still remembered; a save that finished
    /// anyway still counts.
    @discardableResult
    public func save() async -> Record? {
        guard canSave else { return nil }
        state = .saving
        let draft = draft
        let environment = environment
        let saving = Task { try await self.store(draft) }
        let deadline = Task {
            do {
                try await environment.sleep(for: environment.timings.editorDeadline)
            } catch {
                return false
            }
            saving.cancel()
            return true
        }
        let outcome = await saving.result
        deadline.cancel()
        let timedOut = await deadline.value
        createUnconfirmed = creation.isUnconfirmed
        switch outcome {
        case .success(let record):
            if isNew { failedLinks = await PendingLink.send(links, from: record.id, client: client) }
            state = .saved(record)
            return record
        case .failure(let error):
            let failure = EnchiridionError.classify(error) ?? (timedOut ? .unreachable : nil)
            if failure == .notFound, let id = draft.id { vanished = id }
            state = failure.map(SaveState.failed) ?? .editing
            return nil
        }
    }

    /// Adds the links that failed after the create, again.
    public func retryLinks() async {
        guard case .saved(let record) = state, !failedLinks.isEmpty else { return }
        failedLinks = await PendingLink.send(failedLinks, from: record.id, client: client)
    }

    /// Creates `draft`, or sends an edit's update (its changes and any earlier attempt's fields), and reports it.
    private func store(_ draft: RecordDraft) async throws -> Record {
        guard let id = draft.id, var update = draft.update(from: initial) else {
            let record = try await creation.create(draft.input(slug: ""), base: draft.slugBase)
            onChange?(.created(record))
            return record
        }
        let fields = (update.fields ?? []).union(attempted)
        if fields.isEmpty {
            let record = try await client.record(id: id).record
            onChange?(.updated(record))
            return record
        }
        update = update.only(fields)
        do {
            let record = try await client.save(update)
            attempted = []
            onChange?(.updated(record))
            return record
        } catch {
            let failure = EnchiridionError.classify(error)
            // Deleted elsewhere: there is nothing left to bring up to date.
            if failure == .notFound { throw error }
            // Anything else may have reached the server (a cancelled request too), so it goes again next time.
            attempted = fields
            // A lost answer: the record may hold the update already. The check may fail the same way; then
            // `attempted` stays, and the next save sends these fields again.
            if failure?.mightHaveLanded == true, let stored = try? await client.record(id: id).record,
               RecordInput(stored).fieldsDiffering(from: update).isDisjoint(with: fields) {
                attempted = []
                onChange?(.updated(stored))
                return stored
            }
            throw error
        }
    }

    /// The editor closed (its sheet went away, however). An edit that found its record deleted elsewhere reports
    /// `.deleted` now, once the error has been read. One closed with an update that may have landed (discarded after
    /// a lost answer) reads the record back and reports it as `.updated`, so the rows and an open detail show what the
    /// server holds rather than what they had. A new record closed with its create unconfirmed looks the record up
    /// (`RecordCreation.abandon()`) and reports it as `.created` when it landed, so the list shows a record that is on
    /// the server. The returned task is that read.
    @discardableResult
    public func close() -> Task<Void, Never>? {
        if let id = vanished {
            vanished = nil
            onChange?(.deleted(id: id))
            return nil
        }
        if isNew {
            guard let finding = creation.abandon() else { return nil }
            createUnconfirmed = false
            let onChange = onChange
            return Task {
                guard let record = await finding.value else { return }
                onChange?(.created(record))
            }
        }
        guard hasUnsettledEdit, let id = initial.id else { return nil }
        attempted = []
        let client = client
        let onChange = onChange
        return Task {
            guard let record = try? await client.record(id: id).record else { return }
            onChange?(.updated(record))
        }
    }
}
