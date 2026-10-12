import AppIntents
import EnchiridionCore
import EnchiridionKit
import EnchiridionUI
import SwiftUI
import WidgetKit

// The Home Screen and Lock Screen widget: a record from the library at random, a new one each hour, opening it on a
// tap (`enchiridion://record/<id>`). One request a day's worth: `RecordShortcuts.sample` picks the hours' records from
// a single index load (ios/ARCHITECTURE.md, "Widget"). Glue only, like the other targets.

@main
struct EnchiridionWidgets: WidgetBundle {
    init() {
        // The extension is its own process with its own bundle, which carries the font files too.
        FontRegistry.register(bundle: .main)
    }

    var body: some Widget {
        RandomRecordWidget()
    }
}

/// The widget's options: curated records only (the default), or anything.
struct RandomRecordConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Random record"
    static let description = IntentDescription("A record from Enchiridion, a new one each hour.")

    @Parameter(title: "Curated only", default: true)
    var curatedOnly: Bool
}

struct RandomRecordWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RandomRecord", intent: RandomRecordConfiguration.self,
                               provider: RandomRecordProvider()) { entry in
            RecordWidgetView(entry: entry)
                .containerBackground(for: .widget) { Palette.page.view }
        }
        .configurationDisplayName("Random record")
        .description("A record from Enchiridion, a new one each hour.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

/// What a widget shows: a record, else why there's none.
struct RecordWidgetEntry: TimelineEntry {
    struct Shown: Hashable {
        var id: Int
        var title: String
        var typeName: String
        var symbolName: String
        var summary: String?
        var domain: String?
    }

    var date: Date
    var record: Shown?
    var message: String?

    static let sample = RecordWidgetEntry(
        date: .now,
        record: Shown(id: 0, title: "Appropriate uses for SQLite", typeName: "Artifact", symbolName: "shippingbox",
                      summary: "Situations where SQLite works well, and where a client/server database is better.",
                      domain: "sqlite.org"))
}

extension RecordWidgetEntry.Shown {
    init(_ row: ListRecord) {
        let title = [row.title, row.content]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let summary = row.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(id: row.id, title: title ?? row.slug, typeName: row.type.displayName, symbolName: row.type.symbolName,
                  summary: summary?.isEmpty == false ? summary : nil, domain: row.domain)
    }
}

struct RandomRecordProvider: AppIntentTimelineProvider {
    /// Records per load: one an hour.
    static let hours = 12

    func placeholder(in context: Context) -> RecordWidgetEntry { .sample }

    func snapshot(for configuration: RandomRecordConfiguration, in context: Context) async -> RecordWidgetEntry {
        if context.isPreview { return .sample }
        return await timeline(for: configuration, in: context).entries.first ?? .sample
    }

    func timeline(for configuration: RandomRecordConfiguration, in context: Context) async
        -> Timeline<RecordWidgetEntry> {
        let now = Date.now
        do {
            let rows = try await RecordShortcuts(environment: .shareExtension(server: Self.server), role: .widget)
                .sample(Self.hours, curatedOnly: configuration.curatedOnly)
            guard !rows.isEmpty else {
                let entry = RecordWidgetEntry(date: now, message: "Nothing to show yet.")
                return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(6 * 3600)))
            }
            let entries = rows.enumerated().map { hour, row in
                RecordWidgetEntry(date: now.addingTimeInterval(Double(hour) * 3600), record: .init(row))
            }
            return Timeline(entries: entries, policy: .atEnd)
        } catch {
            // Tailscale off, voyager restarting: say so, and try again in a while.
            let entry = RecordWidgetEntry(date: now, message: RecordShortcuts.message(for: error))
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60)))
        }
    }

    /// `Server.production`; a DEBUG build may name a sandbox in its Info.plist, as the share extension does.
    private static var server: URL {
        #if DEBUG
        Server.fromInfoDictionary(.main) ?? Server.production
        #else
        Server.production
        #endif
    }
}

struct RecordWidgetView: View {
    let entry: RecordWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let record = entry.record {
                switch family {
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 1) {
                        Label(record.typeName, systemImage: record.symbolName)
                            .font(.caption2)
                            .widgetAccentable()
                        Text(verbatim: record.title)
                            .font(.headline)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                default:
                    card(record)
                }
            } else {
                Text(verbatim: entry.message ?? "Nothing to show yet.")
                    .font(Typography.stateMessage)
                    .foregroundStyle(Palette.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .widgetURL(entry.record.map { DeepLink.record($0.id) })
    }

    private func card(_ record: RecordWidgetEntry.Shown) -> some View {
        VStack(alignment: .leading, spacing: Space.metaGap) {
            Label(record.typeName, systemImage: record.symbolName)
                .font(Typography.byline)
                .foregroundStyle(Palette.textMuted)
            Text(verbatim: record.title)
                .font(Typography.serif(size: family == .systemSmall ? 17 : 19, relativeTo: .headline))
                .foregroundStyle(Palette.textHighlighted)
                .lineLimit(family == .systemSmall ? 4 : 2)
            if family != .systemSmall, let summary = record.summary {
                Text(verbatim: summary)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.text)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            if let domain = record.domain {
                Text(verbatim: domain)
                    .font(Typography.byline)
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if DEBUG
#Preview(as: .systemMedium) {
    RandomRecordWidget()
} timeline: {
    RecordWidgetEntry.sample
}
#endif
