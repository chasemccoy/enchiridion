import AppIntents
import EnchiridionCore
import EnchiridionKit
import EnchiridionUI
import SwiftUI
import UIKit
import WidgetKit

// The Home Screen and Lock Screen widget: an artifact from the library at random, a new one every 15 minutes (or 30, or
// an hour), opening it on a tap (`enchiridion://record/<id>`). One index load picks the next records (`RecordShortcuts.widgetPicks`, highlights always in the pool); the
// medium and large sizes also fetch each record's first image, downsampled (`WidgetContent.thumbnail`), and show its
// summary and content (ios/ARCHITECTURE.md, "Widget"). Glue only, like the other targets.

@main
struct EnchiridionWidgets: WidgetBundle {
    init() {
        // The extension is its own process with its own bundle, which carries the font files too.
        FontRegistry.register(bundle: .main)
        // As the app does: nothing from the server on the device's disk.
        URLCache.keepMediaInMemory()
    }

    var body: some Widget {
        RandomRecordWidget()
    }
}

/// How often the widget moves to its next record. Moving along a timeline costs nothing; only loading a new one counts
/// against WidgetKit's daily refresh budget.
enum RecordInterval: Int, AppEnum {
    case quarterHour = 15
    case halfHour = 30
    case hour = 60

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Interval"
    static let caseDisplayRepresentations: [RecordInterval: DisplayRepresentation] = [
        .quarterHour: "15 minutes",
        .halfHour: "30 minutes",
        .hour: "Hour",
    ]

    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
}

/// The widget's options: curated records only (the default), or anything; and how often it changes.
struct RandomRecordConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Random record"
    static let description = IntentDescription("A record from Enchiridion, a new one every few minutes.")

    @Parameter(title: "Curated only", default: true)
    var curatedOnly: Bool

    @Parameter(title: "New record every", default: .quarterHour)
    var interval: RecordInterval
}

struct RandomRecordWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RandomRecord", intent: RandomRecordConfiguration.self,
                               provider: RandomRecordProvider()) { entry in
            RecordWidgetView(entry: entry)
                .containerBackground(for: .widget) { Palette.page.view }
        }
        .configurationDisplayName("Random record")
        .description("A record from Enchiridion, a new one every few minutes.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular])
    }
}

/// The widget's Try again: running any intent from a widget's button reloads its timeline.
struct ReloadRecordWidget: AppIntent {
    static let title: LocalizedStringResource = "Reload random record"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult { .result() }
}

/// What a widget shows: a record, else why there's none.
struct RecordWidgetEntry: TimelineEntry {
    struct Shown: Hashable {
        var id: Int
        /// The title; for an untitled record (a highlight), the start of its content.
        var title: String
        var typeName: String
        var symbolName: String
        var summary: String?
        /// The content as plain text, unless it's what the title already shows.
        var content: String?
        var domain: String?
        /// The record's `created_by` link: "Robin Sloan".
        var creator: String?
        /// The first image, downsampled JPEG; only for the sizes that show one.
        var image: Data?
        /// A highlight's passage, shown as the quote it is in place of a title.
        var quote: String? = nil
        /// The title of the record a highlight sits in: "from <source>".
        var source: String? = nil
    }

    var date: Date
    var record: Shown?
    var message: String?
    /// A failed load: the widget offers Try again.
    var canRetry = false

    static let sample = RecordWidgetEntry(
        date: .now,
        record: Shown(id: 0, title: "Appropriate uses for SQLite", typeName: "Artifact", symbolName: "shippingbox",
                      summary: "Situations where SQLite works well, and where a client/server database is better.",
                      content: "SQLite does not compete with client/server databases. SQLite competes with fopen().",
                      domain: "sqlite.org", creator: "D. Richard Hipp"))
}

extension RecordWidgetEntry.Shown {
    /// A highlight (an untitled record inside another) as its passage, credited to the record it's from and that
    /// record's creator and site; anything else as itself.
    init(_ pick: RecordShortcuts.Pick, image: Data? = nil) {
        let row = pick.record
        let untitled = row.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        guard let parent = row.parent, untitled, let quote = WidgetContent.excerpt(row.content, limit: 700) else {
            self.init(row, image: image)
            return
        }
        let source = parent.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let creator = (pick.parent?.creator?.title ?? row.creator?.title)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(id: row.id, title: source?.isEmpty == false ? source! : parent.slug, typeName: "Highlight",
                  symbolName: Symbol.quote, summary: nil, content: nil, domain: pick.parent?.domain ?? row.domain,
                  creator: creator?.isEmpty == false ? creator : nil, image: nil, quote: quote,
                  source: source?.isEmpty == false ? source : parent.slug)
    }

    init(_ row: ListRecord, image: Data? = nil) {
        let excerpt = WidgetContent.excerpt(row.content)
        let title = row.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let titled = title?.isEmpty == false
        let summary = row.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(id: row.id,
                  title: titled ? title! : (excerpt?.split(whereSeparator: \.isNewline).first.map(String.init) ?? row.slug),
                  typeName: row.type.displayName, symbolName: row.type.symbolName,
                  summary: summary?.isEmpty == false ? summary : nil,
                  content: titled ? excerpt : nil,
                  domain: row.domain,
                  creator: row.creator.flatMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }
                      .flatMap { $0.isEmpty ? nil : $0 },
                  image: image)
    }
}

struct RandomRecordProvider: AppIntentTimelineProvider {
    /// Records per load: 12 hours' worth, at most 48. At most 12 for the sizes that fetch an image per record, so a
    /// refresh stays short and its images stay small in memory. Either way, a few loads a day, far inside the budget
    /// (iOS gives a widget roughly 40 to 70).
    static func count(_ family: WidgetFamily, interval: RecordInterval) -> Int {
        let halfDay = Int(12 * 3600 / interval.seconds)
        return min(halfDay, imageSize(family) == nil ? 48 : 12)
    }

    /// The longest side, in pixels, of a size's image; nil for the sizes without one.
    static func imageSize(_ family: WidgetFamily) -> Int? {
        switch family {
        case .systemMedium: 480
        case .systemLarge, .systemExtraLarge: 1000
        default: nil
        }
    }

    func placeholder(in context: Context) -> RecordWidgetEntry { .sample }

    func snapshot(for configuration: RandomRecordConfiguration, in context: Context) async -> RecordWidgetEntry {
        if context.isPreview { return .sample }
        return await timeline(for: configuration, in: context).entries.first ?? .sample
    }

    func timeline(for configuration: RandomRecordConfiguration, in context: Context) async
        -> Timeline<RecordWidgetEntry> {
        let now = Date.now
        do {
            let picks = try await RecordShortcuts(environment: .shareExtension(server: Self.server), role: .widget)
                .widgetPicks(Self.count(context.family, interval: configuration.interval),
                             curatedOnly: configuration.curatedOnly,
                             type: .artifact,
                             imagesEvery: Self.imageSize(context.family) != nil)
            let rows = picks.map(\.record)
            guard !rows.isEmpty else {
                let entry = RecordWidgetEntry(date: now, message: "Nothing to show yet.")
                return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(6 * 3600)))
            }
            let images = await Self.images(for: rows, maxPixelSize: Self.imageSize(context.family))
            let entries = picks.enumerated().map { index, pick in
                RecordWidgetEntry(date: now.addingTimeInterval(Double(index) * configuration.interval.seconds),
                                  record: .init(pick, image: images[pick.record.id]))
            }
            return Timeline(entries: entries, policy: .atEnd)
        } catch {
            // Tailscale off, voyager restarting: say so (with Try again), and try again on its own in a while.
            let entry = RecordWidgetEntry(date: now, message: RecordShortcuts.message(for: error), canRetry: true)
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60)))
        }
    }

    /// Each record's first image, downsampled, fetched side by side; a record whose image doesn't load just shows
    /// without one. Memory-only (`ephemeral`), like every other media load.
    private static func images(for rows: [ListRecord], maxPixelSize: Int?) async -> [Int: Data] {
        guard let maxPixelSize else { return [:] }
        let server = server
        let session = URLSession(configuration: .ephemeral)
        return await withTaskGroup(of: (Int, Data?).self) { group in
            for row in rows {
                guard let media = row.media.first(where: \.isImage), let url = media.url(relativeTo: server) else {
                    continue
                }
                group.addTask {
                    let request = URLRequest(url: url, timeoutInterval: 10)
                    guard let (data, response) = try? await session.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return (row.id, nil) }
                    return (row.id, WidgetContent.thumbnail(data, maxPixelSize: maxPixelSize))
                }
            }
            var images: [Int: Data] = [:]
            for await (id, image) in group {
                if let image { images[id] = image }
            }
            return images
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
                        Label(record.creator ?? record.source ?? record.typeName, systemImage: record.symbolName)
                            .font(.caption2)
                            .widgetAccentable()
                        Text(verbatim: record.quote ?? record.title)
                            .font(record.quote == nil ? .headline : .subheadline)
                            .lineLimit(record.quote == nil ? 2 : 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .systemSmall:
                    SmallRecord(record: record)
                case .systemMedium:
                    MediumRecord(record: record)
                default:
                    LargeRecord(record: record)
                }
            } else {
                VStack(alignment: .leading, spacing: Space.metaGap) {
                    Text(verbatim: entry.message ?? "Nothing to show yet.")
                        .font(Typography.stateMessage)
                        .foregroundStyle(Palette.textMuted)
                    Spacer(minLength: 0)
                    if entry.canRetry, family != .accessoryRectangular {
                        Button(intent: ReloadRecordWidget()) {
                            Label("Try again", systemImage: Symbol.retry)
                                .font(Typography.byline)
                        }
                        .tint(Palette.primary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .widgetURL(entry.record.map { DeepLink.record($0.id) })
    }
}

/// The record's type, small and muted, above its title.
private struct TypeLine: View {
    let record: RecordWidgetEntry.Shown

    var body: some View {
        // A Label's system gap is wide at this size: the icon sits as close as a badge's does.
        HStack(spacing: Space.iconGap) {
            Image(systemName: record.symbolName)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(verbatim: record.typeName)
        }
        .font(Typography.byline)
        .foregroundStyle(Palette.textMuted)
        .lineLimit(1)
    }
}

private struct WidgetTitle: View {
    let text: String
    var size: CGFloat = 17
    var lines: Int

    var body: some View {
        Text(verbatim: text)
            .font(Typography.serif(size: size, relativeTo: .headline))
            .foregroundStyle(Palette.textHighlighted)
            .lineLimit(lines)
            // A long title shrinks a little before it truncates.
            .minimumScaleFactor(0.85)
    }
}

/// The summary, else the content: the record's words below the title.
private struct WidgetBody: View {
    let text: String
    var lines: Int

    var body: some View {
        Text(verbatim: text)
            .font(Typography.cardBody)
            .lineSpacing(Typography.bodyLineSpacing)
            .foregroundStyle(Palette.text)
            .lineLimit(lines)
    }
}

/// Who made it and where it lives: "by Robin Sloan · robinsloan.com", either half alone; a highlight's adds what it's
/// from ("from Tiny internets · by Robin Sloan").
private struct DomainLine: View {
    let record: RecordWidgetEntry.Shown

    var body: some View {
        let parts = record.quote != nil
            ? [record.source.map { "from \($0)" }, record.creator.map { "by \($0)" }].compactMap(\.self)
            : [record.creator.map { "by \($0)" }, record.domain].compactMap(\.self)
        if !parts.isEmpty {
            Text(verbatim: parts.joined(separator: " · "))
                .font(Typography.byline)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
        }
    }
}

/// A highlight's passage in the serif, as the widget's main text.
private struct WidgetQuote: View {
    let text: String
    var size: CGFloat
    var lines: Int

    var body: some View {
        Text(verbatim: "“\(text)”")
            .font(Typography.serif(size: size, relativeTo: .body))
            .lineSpacing(2)
            .foregroundStyle(Palette.textHighlighted)
            .lineLimit(lines)
    }
}

/// A downsampled image, filling its frame.
private struct WidgetPicture: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(Radius.shape(Radius.image))
                .accessibilityHidden(true)
        }
    }
}

/// Type, title, creator and domain: the small size has no room for more.
private struct SmallRecord: View {
    let record: RecordWidgetEntry.Shown

    var body: some View {
        VStack(alignment: .leading, spacing: Space.metaGap) {
            // A highlight drops the type line: its quote takes that line too.
            if let quote = record.quote {
                WidgetQuote(text: quote, size: 15, lines: 6)
            } else {
                TypeLine(record: record)
                WidgetTitle(text: record.title, size: 19, lines: 4)
            }
            Spacer(minLength: 0)
            DomainLine(record: record)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Words on the left (type, title, summary or content, creator and domain), the image on the right when there is one.
private struct MediumRecord: View {
    let record: RecordWidgetEntry.Shown

    var body: some View {
        HStack(spacing: Space.cardPadding) {
            VStack(alignment: .leading, spacing: Space.iconGap) {
                if let quote = record.quote {
                    WidgetQuote(text: quote, size: 17, lines: 5)
                } else {
                    TypeLine(record: record)
                    WidgetTitle(text: record.title, size: 20, lines: 2)
                }
                if let text = record.summary ?? record.content {
                    WidgetBody(text: text, lines: 3)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                DomainLine(record: record)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let image = record.image {
                WidgetPicture(data: image)
                    .frame(width: 120)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

/// The image across the top, then type, title, summary and content, as much as fits, and the creator and domain.
private struct LargeRecord: View {
    let record: RecordWidgetEntry.Shown
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: Space.metaGap) {
            if let image = record.image {
                WidgetPicture(data: image)
                    .frame(height: family == .systemExtraLarge ? 200 : 140)
            }
            VStack(alignment: .leading, spacing: Space.iconGap) {
                if let quote = record.quote {
                    WidgetQuote(text: quote, size: 21, lines: 14)
                } else {
                    TypeLine(record: record)
                    WidgetTitle(text: record.title, size: 24, lines: 3)
                }
            }
            if let summary = record.summary {
                WidgetBody(text: summary, lines: 4)
            }
            if let content = record.content {
                WidgetBody(text: content, lines: record.image == nil ? 12 : 6)
                    .foregroundStyle(Palette.textMuted)
            }
            Spacer(minLength: 0)
            DomainLine(record: record)
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

#Preview(as: .systemLarge) {
    RandomRecordWidget()
} timeline: {
    RecordWidgetEntry.sample
}
#endif
