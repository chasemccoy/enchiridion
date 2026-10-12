import EnchiridionKit
import Foundation
import Observation

/// What the share sheet handed over, after the extension turned its item providers into Sendable values.
public struct ShareInput: Equatable, Sendable {
    public var url: URL?
    public var title: String?
    /// Text selected on the page, or several lines shared along with a URL.
    public var selection: String?
    /// Text shared without a web page.
    public var text: String?
    /// The page's meta description (`description` in Safari's preprocessing results).
    public var summary: String?

    public init(url: URL? = nil, title: String? = nil, selection: String? = nil, text: String? = nil,
                summary: String? = nil) {
        self.url = url
        self.title = title
        self.selection = selection
        self.text = text
        self.summary = summary
    }

    /// Safari's preprocessing results (`{url, title, selection, description}`) first, then a URL item, then plain
    /// text; nil when there is nothing usable.
    ///
    /// A web URL item that comes with text keeps the text too: one line becomes the title (an app sharing a page's
    /// name), several lines the selection. Plain text that is just a web URL is shared as that URL; a URL that isn't
    /// a web page (`mailto:`) is shared as text.
    ///
    /// `itemTitle` is the share item's own title (`NSExtensionItem.attributedTitle`): a page's title when Safari's
    /// preprocessing didn't give one or didn't run (another app, Safari View Controller).
    public static func from(javaScript: [String: String]?, url: URL?, text: String?,
                            itemTitle: String? = nil) -> ShareInput? {
        var input = interpret(javaScript: javaScript, url: url, text: text)
        if input?.url != nil, input?.title == nil, let itemTitle = nonEmpty(itemTitle),
           webURL(itemTitle) == nil {
            input?.title = itemTitle
        }
        return input
    }

    private static func interpret(javaScript: [String: String]?, url: URL?, text: String?) -> ShareInput? {
        if let javaScript, let page = webURL(javaScript["url"]) {
            return ShareInput(url: page, title: nonEmpty(javaScript["title"]),
                              selection: nonEmpty(javaScript["selection"]),
                              summary: nonEmpty(javaScript["description"]))
        }
        let plain = nonEmpty(text)
        if let url, isWeb(url) {
            var input = ShareInput(url: url)
            if let plain, plain != url.absoluteString {
                if plain.contains(where: \.isNewline) { input.selection = plain } else { input.title = plain }
            }
            return input
        }
        if let plain {
            if let lone = webURL(plain) { return ShareInput(url: lone) }
            return ShareInput(text: plain)
        }
        if let url { return ShareInput(text: url.absoluteString) }
        return nil
    }

    static func isWeb(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") && url.host() != nil
    }

    /// The string as a web URL when it is exactly one, with no spaces.
    static func webURL(_ string: String?) -> URL? {
        guard let trimmed = nonEmpty(string), !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), isWeb(url)
        else { return nil }
        return url
    }

    static func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// The share card's fields: the web's add form (the page the browser extension opens) filled from the share. Every
/// field can be edited; links are added after the record is saved.
public struct ShareDraft: Hashable, Sendable {
    public var title: String
    public var type: RecordType
    public var url: String?
    public var note: String
    /// The page's description: the record's summary.
    public var summary: String?
    /// The selection (or shared text): the record's content.
    public var selection: String?
    public var isCurated: Bool
    /// Links the record gets once it's saved, in the order they were added.
    public var links: [PendingLink]

    public init(title: String = "", type: RecordType = .artifact, url: String? = nil, note: String = "",
                summary: String? = nil, selection: String? = nil, isCurated: Bool = false,
                links: [PendingLink] = []) {
        self.title = title
        self.type = type
        self.url = url
        self.note = note
        self.summary = summary
        self.selection = selection
        self.isCurated = isCurated
        self.links = links
    }

    /// A page's title on one line (a `document.title` can hold newlines); shared text becomes the content.
    public init(_ input: ShareInput) {
        self.init(title: input.title.map(Self.oneLine) ?? "", url: input.url?.absoluteString,
                  summary: input.summary, selection: input.selection ?? input.text)
    }

    /// Something worth saving: any field that isn't blank.
    public var hasContent: Bool {
        [title, url ?? "", note, summary ?? "", selection ?? ""]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The slug the record would like: from the title, else the URL; "" means a fallback.
    public var slugBase: String {
        RecordSlug.base(title: RecordDraft.line(title), url: url)
    }

    /// The `PUT /record` create: `{type, source: "manual", title, slug, url, isCurated, summary, content: selection,
    /// notes: note}`, blank fields as `null`. Links go separately, once the record has an id.
    public func input(slug: String) -> RecordInput {
        RecordInput(slug: slug, type: type, title: RecordDraft.line(title), url: url.flatMap(RecordDraft.line),
                    isCurated: isCurated, summary: summary.flatMap(RecordDraft.text),
                    content: selection.flatMap(RecordDraft.text), notes: RecordDraft.line(note), source: .manual)
    }

    /// Adds a link, or changes how an already linked record is linked.
    public mutating func link(_ link: PendingLink) {
        if let index = links.firstIndex(where: { $0.id == link.id }) {
            links[index] = link
        } else {
            links.append(link)
        }
    }

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// The share extension's card: saves the shared page (or text) as a new record, then adds its links.
///
/// There is no outbox: without App Groups the app can't see what the extension parks, so the save happens here or
/// not at all, and a failure says so (with Retry). A failure that might have been a lost success (a timeout, a
/// dropped connection) is checked before it is shown: a record under the slug the save used, matching what was sent,
/// is the one this share made (`RecordCreation`). Retry checks the same way first, so it never saves twice, and edits
/// made to the title or note before it reach that record. A save has `Timings.shareDeadline` in all; past it the card
/// fails as unreachable rather than hold "Saving…" with Cancel off. A failure after which the record may exist all the
/// same (`mayHaveSaved`) says so: Retry finds it, while sharing again later from a new card would save it twice.
@MainActor @Observable
public final class ShareComposeModel {
    public let input: ShareInput
    public var draft: ShareDraft
    public private(set) var state: SaveState = .editing
    /// The last save failed, but the record may be in Enchiridion all the same (`RecordCreation.isUnconfirmed`): the
    /// card says it couldn't confirm the save, not that nothing was saved.
    public private(set) var mayHaveSaved = false
    /// Links that couldn't be added after the record saved: the card says so, and Retry adds just these.
    public private(set) var failedLinks: [PendingLink] = []

    @ObservationIgnored private let creation: RecordCreation
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private var titleSuggested = false
    /// The link picker's search, on the extension's client.
    @ObservationIgnored public let linkSearch: RecordSearchModel

    public init(input: ShareInput, environment: AppEnvironment) {
        self.input = input
        self.environment = environment
        linkSearch = RecordSearchModel(environment: environment, role: .share)
        draft = ShareDraft(input)
        creation = RecordCreation(client: environment.client(role: .share), fallback: environment.fallbackSlug)
    }

    /// The page's host without `www.`, for the preview row; nil for a text share.
    public var domain: String? {
        guard let host = input.url?.host()?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public var canSave: Bool {
        draft.hasContent && (state == .editing || state.error != nil)
    }

    /// Fills in a title found after the card opened (the page's metadata, fetched by the extension), unless one is
    /// there already or the card has moved on. Only once, so a title cleared on purpose stays cleared.
    public func suggestTitle(_ title: String) {
        guard !titleSuggested, state == .editing,
              draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let title = ShareInput.nonEmpty(title) else { return }
        titleSuggested = true
        draft.title = ShareDraft.oneLine(title)
    }

    /// The record saved but some links didn't: Retry adds them.
    public var canRetryLinks: Bool {
        if case .saved = state { return !failedLinks.isEmpty }
        return false
    }

    /// Adds the links that failed after the save, again (`PUT /link` upserts, so a link that landed after all is
    /// harmless to send twice).
    public func retryLinks() async {
        guard case .saved(let record) = state, !failedLinks.isEmpty else { return }
        failedLinks = await Self.addLinks(failedLinks, to: record.id, client: environment.client(role: .share))
    }

    /// Sends each link; returns the ones that failed.
    private static func addLinks(_ links: [PendingLink], to recordID: Int,
                                 client: EnchiridionClient) async -> [PendingLink] {
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

    /// Saves the record; `state` ends `.saved` or `.failed`. Callable again after a failure (Retry).
    ///
    /// The save races `Timings.shareDeadline`. When the deadline wins, the save is cancelled (URLSession stops its
    /// request) and awaited, so `RecordCreation` still knows a create that may have landed; a save that finished
    /// anyway still counts.
    public func save() async {
        guard canSave else { return }
        state = .saving
        let draft = draft
        let creation = creation
        let environment = environment
        let saving = Task { try await creation.create(draft.input(slug: ""), base: draft.slugBase) }
        let deadline = Task {
            do {
                try await environment.sleep(for: environment.timings.shareDeadline)
            } catch {
                return false
            }
            saving.cancel()
            return true
        }
        let outcome = await saving.result
        deadline.cancel()
        let timedOut = await deadline.value
        mayHaveSaved = creation.isUnconfirmed
        switch outcome {
        case .success(let record):
            failedLinks = await Self.addLinks(draft.links, to: record.id, client: environment.client(role: .share))
            state = .saved(record)
        case .failure(let error) where timedOut:
            state = .failed(EnchiridionError.classify(error) ?? .unreachable)
        case .failure(let error):
            state = EnchiridionError.classify(error).map(SaveState.failed) ?? .editing
        }
    }
}
