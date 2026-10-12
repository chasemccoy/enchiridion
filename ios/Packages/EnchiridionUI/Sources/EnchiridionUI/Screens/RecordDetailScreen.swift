import EnchiridionCore
import EnchiridionKit
import SwiftUI

/// One record, as the web's `RecordDetail` shows it, read-only with Edit for changes: the badge row (Needs curating,
/// the type, the source unless manual, the captured date, the id), the title in the serif, the byline (from the parent,
/// by the creator, at the domain), the record's images, its content as Markdown (single newlines kept as line breaks),
/// a Details card (Summary, Link, Published, Notes), then "Linked records", a card per predicate. In a column at most
/// 680 pt wide, centered. Edit is in the navigation bar; Curate, Open, Share and Delete are in the bottom bar.
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
                    DetailContent(detail: detail, model: model, titleScrolledAway: $titleScrolledAway)
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

private struct DetailContent: View {
    let detail: RecordDetail
    let model: RecordDetailModel
    @Binding var titleScrolledAway: Bool

    var body: some View {
        let record = detail.record
        VStack(alignment: .leading, spacing: Space.detailGap) {
            if let error = model.state.error {
                StatusBanner(error: error) {
                    Task { await model.refresh() }
                }
            }
            BadgeRow(record: record)
            VStack(alignment: .leading, spacing: Space.metaGap) {
                DetailTitle(title: record.title.nonBlank, scrolledAway: $titleScrolledAway)
                Byline(detail: detail)
            }
            DetailImages(media: detail.media)
            if let content = record.content.nonBlank {
                MarkdownText(content, size: .regular)
                    .textSelection(.enabled)
            }
            DetailsCard(record: record)
            LinkedRecords(groups: model.linkGroups)
        }
        .frame(maxWidth: Metrics.detailWidth, alignment: .leading)
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.metaGap)
        .padding(.bottom, Space.monthGap)
        .frame(maxWidth: .infinity)
    }
}

/// Needs curating, the type (always, artifact included), the source unless manual, the captured date and time, the id.
private struct BadgeRow: View {
    let record: Record

    var body: some View {
        FlowLayout(spacing: Space.badgeGap, lineSpacing: Space.badgeGap) {
            if !record.isCurated {
                Badge("Needs curating", systemImage: Symbol.needsCuration)
            }
            TypeBadge(record.type)
            if let source = record.source, source != .manual {
                Badge(source.displayName, systemImage: source.symbolName)
            }
            if let captured = record.recordCreatedAt.text(.captured) {
                Badge(captured, systemImage: Symbol.captured)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "Captured \(captured)"))
            }
            Badge(String(record.id), systemImage: Symbol.recordID)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "Record \(record.id)"))
        }
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

/// "from <parent>", "by <creator>" (each opening that record) and "at <domain>", in muted 13 pt text.
private struct Byline: View {
    let detail: RecordDetail

    var body: some View {
        let parent = detail.targets(.containedBy).first ?? detail.targets(.quotes).first
        let creator = detail.creator
        let domain = detail.record.domain
        if parent != nil || creator != nil || domain != nil {
            FlowLayout(spacing: Space.metaGap, lineSpacing: Space.iconGap) {
                if let parent {
                    BylineLink(prefix: "from", systemImage: Symbol.parent, record: parent)
                }
                if let creator {
                    BylineLink(prefix: "by", systemImage: Symbol.creator, record: creator)
                }
                if let domain {
                    DomainLabel(domain, font: Typography.detailByline)
                }
            }
        }
    }
}

private struct BylineLink: View {
    let prefix: String
    let systemImage: String
    let record: Record
    @ScaledMetric(relativeTo: .footnote) private var iconSize = Metrics.metadataIcon

    var body: some View {
        let name = record.title.nonBlank ?? record.slug
        NavigationLink(value: RecordRoute(id: record.id)) {
            HStack(spacing: Space.iconGap) {
                Text(verbatim: prefix)
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                    .foregroundStyle(Palette.textDimmed)
                    .accessibilityHidden(true)
                Text(verbatim: name)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .font(Typography.detailByline)
            .foregroundStyle(Palette.textMuted)
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
/// Curate fills once the record is curated (the badge row says "Needs curating" until then). Everything waits while a
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

/// Summary, Link, Published and Notes, each only when the record has it: a grouped card, each label above its value
/// (there's no room for a label column on a phone). The link opens in the in-app browser.
private struct DetailsCard: View {
    let record: Record

    var body: some View {
        let summary = record.summary.nonBlank
        let url = record.url.nonBlank
        let published = record.contentCreatedAt?.text(.published)
        let notes = record.notes.nonBlank
        if summary != nil || url != nil || published != nil || notes != nil {
            VStack(alignment: .leading, spacing: Metrics.groupedCaptionGap) {
                GroupedCardLabel(text: "Details")
                GroupedCard {
                    if let summary {
                        DetailRow("Summary", systemImage: Symbol.summary) {
                            Text(verbatim: summary).textSelection(.enabled)
                        }
                    }
                    if let url {
                        LinkRow(url: url)
                    }
                    if let published {
                        DetailRow("Published", systemImage: Symbol.published) {
                            Text(verbatim: published)
                        }
                    }
                    if let notes {
                        DetailRow("Notes", systemImage: Symbol.notes) {
                            Text(verbatim: notes).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

/// A Details row: a small muted label with its symbol, the value under it.
private struct DetailRow<Value: View>: View {
    let label: String
    let systemImage: String
    let value: Value
    @ScaledMetric(relativeTo: .caption) private var iconSize = Metrics.metadataIcon

    init(_ label: String, systemImage: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.systemImage = systemImage
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.iconGap) {
            HStack(spacing: Space.iconGap) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                    .foregroundStyle(Palette.textDimmed)
                    .accessibilityHidden(true)
                Text(verbatim: label)
                    .font(Typography.metadataLabel)
                    .foregroundStyle(Palette.textMuted)
            }
            value
                .font(Typography.metadataValue)
                .foregroundStyle(Palette.text)
                .wrapsFully()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Metrics.groupedRowPadding)
        .accessibilityElement(children: .combine)
    }
}

/// The Link row: the address in `primary`, tapping it opens the in-app browser. An address that isn't a web link
/// shows as plain, selectable text.
private struct LinkRow: View {
    let url: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let link = RecordURL.web(url) {
            Button {
                openURL(link)
            } label: {
                HStack(alignment: .center, spacing: Space.metaGap) {
                    DetailRow("Link", systemImage: Symbol.url) {
                        Text(verbatim: url)
                            .foregroundStyle(Palette.primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .padding(.trailing, -Metrics.groupedRowPadding.trailing)
                    Image(systemName: Symbol.browser)
                        .font(Typography.count.weight(.semibold))
                        .foregroundStyle(Palette.textDimmed)
                        .padding(.trailing, Metrics.groupedRowPadding.trailing)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityHint("Opens the page")
        } else {
            DetailRow("Link", systemImage: Symbol.url) {
                Text(verbatim: url).textSelection(.enabled)
            }
        }
    }
}

/// "Linked records": a grouped card per predicate as it reads from this record ("Created by", "Tagged with"), its
/// label above it. Each row opens its record.
private struct LinkedRecords: View {
    let groups: [LinkGroup]

    var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: Space.detailGap) {
                Text("Linked records")
                    .font(Typography.sectionHeading)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: Metrics.groupedCaptionGap) {
                        GroupedCardLabel(text: group.label)
                        GroupedCard {
                            ForEach(group.links) { link in
                                NavigationLink(value: RecordRoute(id: link.recordID)) {
                                    LinkedRecordRow(link: link)
                                }
                                .buttonStyle(RowButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(.top, Space.metaGap)
        }
    }
}

private struct LinkedRecordRow: View {
    let link: LinkedRecord

    var body: some View {
        let titled = link.title.nonBlank != nil
        HStack(alignment: .center, spacing: Space.metaGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: link.displayTitle)
                    .font(titled ? Typography.linkTitle : Typography.cardBody)
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
        .padding(Metrics.groupedRowPadding)
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
