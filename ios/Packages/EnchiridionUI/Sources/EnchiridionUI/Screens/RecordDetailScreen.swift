import EnchiridionCore
import EnchiridionKit
import struct EnchiridionKit.Predicate
import SwiftUI

/// One record, read-only with Edit for changes, laid out as a ledger with one left edge and no boxes (`DetailContent`):
/// a muted line of facts, the title in the serif, the byline, the summary and note, the images, the content as
/// Markdown (single newlines kept as line breaks), a Link/Published table, then "Linked records" (Add link, a row's
/// Remove link) and "Similar records" as plain rows under their labels. In a column at most 680 pt wide, centered. Edit is in the navigation bar; Curate, Open, Share and Delete are in the bottom bar.
///
/// Links (a linked record, the parent, the creator) push a `RecordRoute`; the stack this screen sits in registers its
/// destination (`LibraryScreen` does). `onDeleted` runs once a delete from here succeeds: a pushed screen pops itself
/// with it, while the selected record's screen needs nothing, since the library selects the record that took its place.
/// `onEdit` presents Edit's editor somewhere that outlives this screen (`LibraryScreen` presents it above the split
/// view, so a reload that moves the selection never takes the sheet and its typed text with it); without it, this
/// screen presents the editor itself.
///
/// Before the record loads, a spinner or the load's error (the not-allowed state for a 401 that names this device); a
/// failed refresh of a loaded record shows above it with Retry. A failed load is tried again when the app comes back.
public struct RecordDetailScreen: View {
    let model: RecordDetailModel
    let onDeleted: (() -> Void)?
    let onEdit: ((RecordEditorModel) -> Void)?
    @State private var editor: EditorSession?
    @State private var linking: LinkSession?
    @State private var confirmingDelete = false
    @State private var titleScrolledAway = false
    @Environment(\.scenePhase) private var scenePhase

    public init(model: RecordDetailModel, onDeleted: (() -> Void)? = nil,
                onEdit: ((RecordEditorModel) -> Void)? = nil) {
        self.model = model
        self.onDeleted = onDeleted
        self.onEdit = onEdit
    }

    public var body: some View {
        Group {
            if let detail = model.detail {
                ScrollView {
                    DetailContent(detail: detail, model: model, titleScrolledAway: $titleScrolledAway) {
                        linking = LinkSession(search: model.makeLinkSearch())
                    }
                }
                .refreshable { await model.refresh() }
            } else if let error = model.state.error {
                ErrorState(error) { retry() }
                    .padding(Space.margin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LoadingIndicator(label: "Loading the record")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.page)
        // The serif title is the screen's heading; the bar shows it only once it has scrolled away.
        .navigationTitle(Text(verbatim: titleScrolledAway ? model.record.map(Self.barTitle) ?? "" : ""))
        .inlineNavigationTitle()
        .toolbar {
            if let record = model.record {
                DetailToolbar(record: record, model: model, edit: edit, confirmingDelete: $confirmingDelete)
            }
        }
        .task { await model.load() }
        .onChange(of: model.isDeleted) { _, deleted in
            if deleted { onDeleted?() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.state.error != nil { retry() }
        }
        .sheet(item: $editor) { session in
            RecordEditorSheet(model: session.model)
        }
        .sheet(item: $linking) { session in
            LinkPickerSheet(search: session.search) { row, predicate in
                Task { await model.addLink(to: row.id, predicate: predicate) }
            }
        }
        .confirmationDialog("Delete this record?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete record", role: .destructive) {
                Task { await model.delete() }
            }
        } message: {
            Text(verbatim: RecordName.deletion(model.record?.title))
        }
        .actionErrorAlert(model.actionError) { model.clearActionError() }
    }

    private func retry() {
        Task { await model.refresh() }
    }

    private func edit() {
        guard let editorModel = model.makeEditor() else { return }
        if let onEdit {
            onEdit(editorModel)
        } else {
            editor = EditorSession(model: editorModel)
        }
    }

    /// The title, else the start of the content (a highlight), else "Untitled record".
    static func barTitle(_ record: Record) -> String {
        for text in [record.title, record.content] {
            if let line = text?.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespaces),
               !line.isEmpty {
                return line
            }
        }
        return "Untitled record"
    }
}

/// The record as a ledger: one left edge for everything. A muted line of facts (needs curating, type, source, when
/// it was saved, its number), the serif title, who made it and what it's from, the summary as a muted introduction,
/// the note's bubble, the images, the content, then a two-column table of the link and the published date, and the
/// linked and similar records as plain rows under their labels. No boxes: hairlines run margin to margin.
private struct DetailContent: View {
    let detail: RecordDetail
    let model: RecordDetailModel
    @Binding var titleScrolledAway: Bool
    let addLink: () -> Void

    var body: some View {
        let record = detail.record
        VStack(alignment: .leading, spacing: 0) {
            if let error = model.state.error {
                StatusBanner(error: error) {
                    Task { await model.refresh() }
                }
                .padding(.bottom, Space.detailGap)
            }
            MetaLine(record: record)
            DetailTitle(title: record.title.nonBlank, scrolledAway: $titleScrolledAway)
                .padding(.top, Metrics.ledgerTitleGap)
            Byline(detail: detail)
                .padding(.top, Space.iconGap)
            if let summary = record.summary.nonBlank?.trimmingLineEnds {
                Text(verbatim: summary)
                    .font(Typography.ledgerSummary)
                    .lineSpacing(Typography.bodyLineSpacing)
                    .foregroundStyle(Palette.textMuted)
                    .textSelection(.enabled)
                    .wrapsFully()
                    .padding(.top, Metrics.ledgerSummaryGap)
            }
            if let notes = record.notes.nonBlank?.trimmingLineEnds {
                NoteBubble(notes)
                    .textSelection(.enabled)
                    .padding(.top, Metrics.ledgerNoteGap)
            }
            DetailImages(media: detail.media)
                .padding(.top, detail.media.contains(where: \.isImage) ? Space.detailGap : 0)
            if let content = record.content.nonBlank {
                MarkdownText(content, size: .regular)
                    .textSelection(.enabled)
                    .padding(.top, Space.detailGap)
            }
            FactsTable(record: record)
            LinkedRecords(model: model, addLink: addLink)
            SimilarRecords(model: model)
        }
        .frame(maxWidth: Metrics.detailWidth, alignment: .leading)
        .padding(.horizontal, Metrics.detailMargin)
        .padding(.top, Space.metaGap)
        .padding(.bottom, Space.monthGap)
        .frame(maxWidth: .infinity)
        // Exactly the screen's width: a view that measures a little wider than it draws can never widen the page
        // into a sideways scroll.
        .containerRelativeFrame(.horizontal)
    }
}

/// "Needs curating · Artifact · Readwise · Saved June 28, 2025 at 1:54 PM · #371": the facts the web shows as badges,
/// as one muted line above the title. Needs curating stands out in `text`.
private struct MetaLine: View {
    let record: Record

    var body: some View {
        var parts: [String] = [record.type.displayName]
        if let source = record.source, source != .manual { parts.append(source.displayName) }
        if let saved = record.recordCreatedAt.text(.captured) { parts.append("Saved \(saved)") }
        parts.append("#\(record.id)")
        let facts = Text(verbatim: parts.joined(separator: " · ")).foregroundStyle(Palette.textMuted)
        let line = record.isCurated
            ? facts
            : Text("\(Text("Needs curating").foregroundStyle(Palette.text)) · \(facts)")
        return line
            .font(Typography.ledgerMeta)
            .wrapsFully()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 27 pt Martina Plantijn in `textHighlighted`, selectable; "Untitled record" dimmed when there is no title, as the
/// web's placeholder reads.
private struct DetailTitle: View {
    let title: String?
    @Binding var scrolledAway: Bool

    var body: some View {
        Text(verbatim: title ?? "Untitled record")
            .font(Typography.detailTitle)
            .lineSpacing(Typography.detailTitleLineSpacing)
            .foregroundStyle(title == nil ? Palette.textDimmed : Palette.textHighlighted)
            .textSelection(.enabled)
            .wrapsFully()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .onScrollVisibilityChange(threshold: 0.2) { visible in
                scrolledAway = !visible
            }
    }
}

/// "from <parent>" and "by <creator>", each opening that record, in muted text with the names in `primary`. The
/// domain lives in the facts table's Link row.
private struct Byline: View {
    let detail: RecordDetail

    var body: some View {
        let parent = detail.targets(.containedBy).first ?? detail.targets(.quotes).first
        let creator = detail.creator
        if parent != nil || creator != nil {
            FlowLayout(spacing: Space.metaGap, lineSpacing: Space.iconGap) {
                if let parent {
                    BylineLink(prefix: "from", record: parent)
                }
                if let creator {
                    BylineLink(prefix: "by", record: creator)
                }
            }
        }
    }
}

private struct BylineLink: View {
    let prefix: String
    let record: Record

    var body: some View {
        let name = record.title.nonBlank ?? record.slug
        NavigationLink(value: RecordRoute(id: record.id)) {
            HStack(spacing: Space.iconGap) {
                Text(verbatim: prefix)
                    .foregroundStyle(Palette.textMuted)
                Text(verbatim: name)
                    .foregroundStyle(Palette.primary)
                    .lineLimit(1)
            }
            .font(Typography.ledgerByline)
        }
        .buttonStyle(PressDimButtonStyle())
        .accessibilityLabel(Text(verbatim: "\(prefix) \(name)"))
    }
}

/// The record's images, each as wide as the column (up to `detailImageMaxHeight` tall), on `elevated` while loading.
private struct DetailImages: View {
    let media: [Media]
    @Environment(\.serverURL) private var serverURL

    var body: some View {
        let images = media.filter(\.isImage).compactMap { item in
            item.resolvedURL(server: serverURL).map { (item, $0) }
        }
        if !images.isEmpty {
            VStack(alignment: .leading, spacing: Space.metaGap) {
                ForEach(images, id: \.0.id) { item, url in
                    DetailImage(media: item, url: url)
                }
            }
        }
    }
}

private struct DetailImage: View {
    let media: Media
    let url: URL

    var body: some View {
        let shape = Radius.shape(Radius.image)
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Palette.elevated.view
                    .overlay {
                        if phase.error != nil {
                            Image(systemName: Symbol.image)
                                .foregroundStyle(Palette.textDimmed)
                        }
                    }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxHeight: Metrics.detailImageMaxHeight)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: media.altText.nonBlank ?? "Image"))
    }

    /// The stored size's ratio, so the space is held while the image loads; 4:3 when the size isn't known.
    private var aspectRatio: CGFloat {
        guard let width = media.width, let height = media.height, width > 0, height > 0 else { return 4 / 3 }
        return CGFloat(width) / CGFloat(height)
    }
}

/// The bar items: Edit up top; Curate, Open, Share and Delete in the bottom bar, where iOS draws them in Liquid Glass.
/// Curate fills once the record is curated (the meta line says "Needs curating" until then). Everything waits while a
/// curate or delete is in flight.
private struct DetailToolbar: ToolbarContent {
    let record: Record
    let model: RecordDetailModel
    let edit: () -> Void
    @Binding var confirmingDelete: Bool
    @Environment(\.openURL) private var openURL

    var body: some ToolbarContent {
        let link = RecordURL.web(record.url)
        ToolbarItem(placement: .primaryAction) {
            Button("Edit", action: edit)
                .disabled(model.isWorking)
        }
        ToolbarItem(placement: .bottomBarOrAutomatic) {
            Button {
                Task { await model.setCurated(!record.isCurated) }
            } label: {
                Label(record.isCurated ? "Curated" : "Curate",
                      systemImage: record.isCurated ? Symbol.curated : Symbol.curate)
            }
            .tint(record.isCurated ? Palette.primary : nil)
            .disabled(model.isWorking)
            .accessibilityValue(record.isCurated ? "Curated" : "Needs curating")
        }
        ToolbarSpacer(.flexible, placement: .bottomBarOrAutomatic)
        if let link {
            ToolbarItem(placement: .bottomBarOrAutomatic) {
                Button {
                    openURL(link)
                } label: {
                    Label("Open link", systemImage: Symbol.browser)
                }
            }
            ToolbarItem(placement: .bottomBarOrAutomatic) {
                ShareLink(item: link) {
                    Label("Share", systemImage: Symbol.share)
                }
            }
        }
        ToolbarItem(placement: .bottomBarOrAutomatic) {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete record", systemImage: Symbol.delete)
            }
            .tint(Palette.error)
            .disabled(model.isWorking)
        }
    }
}

/// The link and the published date as a two-column table: the label at the left edge, the value in a column of its
/// own. The link opens in the in-app browser; an address that isn't a web link shows as plain, selectable text.
private struct FactsTable: View {
    let record: Record
    @Environment(\.openURL) private var openURL

    var body: some View {
        let url = record.url.nonBlank
        let published = record.contentCreatedAt?.text(.published)
        if url != nil || published != nil {
            LedgerList {
                if let url {
                    if let link = RecordURL.web(url) {
                        Button {
                            openURL(link)
                        } label: {
                            FactRow("Link") {
                                HStack(spacing: Space.metaGap) {
                                    Text(verbatim: Self.shortened(url))
                                        .foregroundStyle(Palette.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: Symbol.external)
                                        .font(Typography.count.weight(.semibold))
                                        .foregroundStyle(Palette.textDimmed)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(LedgerRowButtonStyle())
                        .accessibilityHint("Opens the page")
                    } else {
                        FactRow("Link") {
                            Text(verbatim: url).textSelection(.enabled)
                        }
                    }
                }
                if let published {
                    FactRow("Published") {
                        Text(verbatim: published)
                    }
                }
            }
            .padding(.top, Metrics.ledgerSectionGap)
        }
    }

    /// The address without its scheme and `www.`: the row already says it's a link.
    static func shortened(_ url: String) -> String {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "www."] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }
}

/// A facts table row: the label in its column, the value beside it.
private struct FactRow<Value: View>: View {
    let label: String
    let value: Value

    init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: label)
                .foregroundStyle(Palette.textMuted)
                .frame(width: Metrics.ledgerLabelWidth, alignment: .leading)
            value
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Typography.ledgerRow)
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }
}

/// "Linked records" with Add link, then a group per predicate as it reads from this record ("Created by", "Tagged
/// with"): its label, then its records as plain rows. Each row opens its record; its context menu removes the link.
private struct LinkedRecords: View {
    let model: RecordDetailModel
    let addLink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Linked records")
                    .font(Typography.ledgerHeading)
                    .foregroundStyle(Palette.textHighlighted)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.metaGap)
                Button("Add link", action: addLink)
                    .font(Typography.ledgerRow)
                    .buttonStyle(.borderless)
                    .tint(Palette.primary)
                    .disabled(model.isLinking)
            }
            ForEach(model.linkGroups) { group in
                LedgerLabel(text: group.label)
                    .padding(.top, Metrics.ledgerGroupGap)
                LedgerList {
                    ForEach(group.links) { link in
                        NavigationLink(value: RecordRoute(id: link.recordID)) {
                            LinkedRecordRow(link: link)
                        }
                        .buttonStyle(LedgerRowButtonStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await model.removeLink(link) }
                            } label: {
                                Label("Remove link", systemImage: Symbol.unlink)
                            }
                        }
                    }
                }
                .padding(.top, Metrics.ledgerLabelGap)
            }
        }
        .padding(.top, Metrics.ledgerHeadingGap)
    }
}

/// "Similar records": the server's nearest records by embedding that aren't linked yet, as plain rows that open
/// their record, each with a menu to link it ("Related to", "About"…). Hidden when there are none (or they couldn't
/// load).
private struct SimilarRecords: View {
    let model: RecordDetailModel

    var body: some View {
        let similar = model.similar
        if !similar.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Similar records")
                    .font(Typography.ledgerHeading)
                    .foregroundStyle(Palette.textHighlighted)
                    .accessibilityAddTraits(.isHeader)
                LedgerList {
                    ForEach(similar) { item in
                        HStack(spacing: Space.metaGap) {
                            NavigationLink(value: RecordRoute(id: item.id)) {
                                SimilarRecordRow(item: item)
                            }
                            .buttonStyle(LedgerRowButtonStyle())
                            Menu {
                                Section("Link as") {
                                    ForEach(Predicate.linkOptions, id: \.self) { predicate in
                                        Button(predicate.menuName) {
                                            Task { await model.addLink(to: item.id, predicate: predicate) }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: Symbol.addLink)
                                    .font(Typography.linkTitle)
                                    .foregroundStyle(Palette.primary)
                                    .frame(minWidth: Metrics.ledgerRowHeight, minHeight: Metrics.ledgerRowHeight)
                                    .contentShape(Rectangle())
                            }
                            .disabled(model.isLinking)
                            .accessibilityLabel(Text(verbatim: "Link \(item.record.title.nonBlank ?? item.record.slug)"))
                        }
                    }
                }
                .padding(.top, Metrics.ledgerLabelGap + Space.iconGap)
            }
            .padding(.top, Metrics.ledgerHeadingGap)
        }
    }
}

/// A similar record: its title, and why it's similar ("50% similar by content").
private struct SimilarRecordRow: View {
    let item: SimilarRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: item.record.title.nonBlank ?? item.record.content.nonBlank ?? item.record.slug)
                .font(Typography.ledgerRow)
                .foregroundStyle(Palette.text)
                .lineLimit(2)
            if let reason = item.reasons.first {
                Text(verbatim: reason)
                    .font(Typography.note)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerRow()
    }
}

private struct LinkedRecordRow: View {
    let link: LinkedRecord

    var body: some View {
        let titled = link.title.nonBlank != nil
        HStack(alignment: .center, spacing: Space.metaGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: link.displayTitle)
                    .font(titled ? Typography.ledgerRow : Typography.cardBody)
                    .foregroundStyle(Palette.text)
                    .lineLimit(titled ? 2 : 3)
                if let notes = link.notes.nonBlank {
                    Text(verbatim: notes)
                        .font(Typography.note)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: Symbol.disclosure)
                .font(Typography.count.weight(.semibold))
                .foregroundStyle(Palette.textDimmed)
                .accessibilityHidden(true)
        }
        .ledgerRow()
    }
}

/// A group's label above its rows ("Created by"), at the left edge.
private struct LedgerLabel: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(Typography.ledgerLabel)
            .foregroundStyle(Palette.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rows with a hairline above the first and below each, margin to margin: the ledger's only divider.
private struct LedgerList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            Group(subviews: content()) { rows in
                ForEach(rows) { row in
                    row
                    Hairline()
                }
            }
        }
    }
}

/// One `border` line, a pixel thick at any scale.
private struct Hairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Palette.border.view
            .frame(height: 1 / displayScale)
            .accessibilityHidden(true)
    }
}

/// A pressable ledger row: `elevated` while pressed, out to the screen's edges beyond the text margin, as a list cell
/// highlights.
private struct LedgerRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Metrics.detailMargin)
            .background {
                if configuration.isPressed {
                    Palette.elevated.view
                }
            }
            .padding(.horizontal, -Metrics.detailMargin)
            .contentShape(Rectangle())
    }
}

extension View {
    /// A ledger row's height and padding: at least the tap target, the text centered in it.
    fileprivate func ledgerRow() -> some View {
        padding(.vertical, Metrics.ledgerRowPadding)
            .frame(minHeight: Metrics.ledgerRowHeight)
            .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("Record") {
    NavigationStack {
        RecordDetailScreen(model: RecordDetailModel(id: PreviewSamples.record.id, environment: .preview()))
            .navigationDestination(for: RecordRoute.self) { route in
                RecordDetailScreen(model: RecordDetailModel(id: route.id, environment: .preview()))
            }
    }
    .previewRoot()
}
#endif
