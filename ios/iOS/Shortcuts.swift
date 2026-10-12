import AppIntents
import EnchiridionCore
import EnchiridionKit
import EnchiridionUI
import LinkPresentation
import UIKit

// Siri and the Shortcuts app: open a record, show one at random, save a link. Glue only: what each action does lives
// in EnchiridionCore's `RecordShortcuts` (ios/ARCHITECTURE.md, "Shortcuts"). App Intents need no entitlement, so the
// free team can ship them; they live in the app target, which runs them in its own process.

/// The actions' client: the same server as the app.
private func shortcuts() -> RecordShortcuts {
    RecordShortcuts(environment: .live(server: AppServer.url))
}

/// A failure as Siri says it: the error's own message (Tailscale off, not on the list, …).
private struct ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    init(_ error: any Error) {
        message = RecordShortcuts.message(for: error)
    }

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

// MARK: The record entity

struct RecordEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Record"
    static let defaultQuery = RecordEntityQuery()

    let id: Int
    @Property(title: "Title") var title: String
    @Property(title: "Link") var link: URL?
    @Property(title: "Summary") var summary: String?
    let typeName: String
    let symbolName: String

    init(id: Int, title: String?, slug: String, type: RecordType, url: String?, summary: String? = nil) {
        self.id = id
        typeName = type.displayName
        symbolName = type.symbolName
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? slug
        link = url.flatMap(URL.init(string:))
        self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    init(_ row: ListRecord) {
        self.init(id: row.id, title: row.title, slug: row.slug, type: row.type, url: row.url, summary: row.summary)
    }

    init(_ record: Record) {
        self.init(id: record.id, title: record.title, slug: record.slug, type: record.type, url: record.url,
                  summary: record.summary)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(typeName)", image: .init(systemName: symbolName))
    }
}

/// Finds records for a Shortcut's or Siri's "which record?": by id, by what's typed or said (hybrid search, as the
/// app's), and the newest ones before anything is.
struct RecordEntityQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [RecordEntity] {
        let shortcuts = shortcuts()
        var found: [RecordEntity] = []
        for id in identifiers {
            if let record = try? await shortcuts.record(id: id) { found.append(RecordEntity(record)) }
        }
        return found
    }

    func entities(matching string: String) async throws -> [RecordEntity] {
        do {
            return try await shortcuts().find(string).map(RecordEntity.init)
        } catch {
            throw ShortcutError(error)
        }
    }

    func suggestedEntities() async throws -> [RecordEntity] {
        do {
            return try await shortcuts().recent().map(RecordEntity.init)
        } catch {
            throw ShortcutError(error)
        }
    }
}

// MARK: Actions

/// Opens a record in the app (through `enchiridion://record/<id>`, which the root view selects).
struct OpenRecordIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open record"
    static let description = IntentDescription("Opens a record in Enchiridion.")

    @Parameter(title: "Record", requestValueDialog: "Which record?")
    var target: RecordEntity

    init() {}

    init(target: RecordEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(DeepLink.record(target.id))
        return .result()
    }
}

/// A record picked at random: curated ones only, unless asked otherwise. Says its title (and summary), and hands the
/// record on to the next action.
struct RandomRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "Random record"
    static let description = IntentDescription("Picks a record from Enchiridion at random.")

    @Parameter(title: "Curated only", default: true)
    var curatedOnly: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<RecordEntity?> & ProvidesDialog {
        let picked: ListRecord?
        do {
            picked = try await shortcuts().random(curatedOnly: curatedOnly)
        } catch {
            throw ShortcutError(error)
        }
        guard let picked else {
            return .result(value: nil, dialog: "There's nothing in Enchiridion to pick from yet.")
        }
        let entity = RecordEntity(picked)
        let said = [entity.title, entity.summary].compactMap { $0 }.joined(separator: ". ")
        return .result(value: entity, dialog: "\(said)")
    }
}

/// Saves a link as a new artifact without opening the app, as the share card would with nothing edited. Without a
/// title, the page's own is fetched.
struct SaveLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Save link"
    static let description = IntentDescription("Saves a web page to Enchiridion.")

    @Parameter(title: "Link", requestValueDialog: "Which link?")
    var url: URL

    @Parameter(title: "Title")
    var title: String?

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$url) to Enchiridion") {
            \.$title
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<RecordEntity> & ProvidesDialog {
        var title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        if title == nil { title = await Self.pageTitle(url) }
        do {
            let record = try await shortcuts().save(url: url, title: title, note: note)
            let entity = RecordEntity(record)
            return .result(value: entity, dialog: "Saved “\(entity.title)”.")
        } catch {
            throw ShortcutError(error)
        }
    }

    /// The page's title from its metadata; nil if it doesn't load in time.
    @MainActor
    private static func pageTitle(_ url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        provider.shouldFetchSubresources = false
        return try? await provider.startFetchingMetadata(for: url).title
    }
}

// MARK: Siri phrases

struct EnchiridionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RandomRecordIntent(),
                    phrases: ["Show me something from \(.applicationName)",
                              "Random record from \(.applicationName)"],
                    shortTitle: "Random record", systemImageName: "shuffle")
        AppShortcut(intent: OpenRecordIntent(),
                    phrases: ["Open a record in \(.applicationName)",
                              "Find a record in \(.applicationName)"],
                    shortTitle: "Open record", systemImageName: "doc.text.magnifyingglass")
        AppShortcut(intent: SaveLinkIntent(),
                    phrases: ["Save a link to \(.applicationName)",
                              "Save this to \(.applicationName)"],
                    shortTitle: "Save link", systemImageName: "link.badge.plus")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
