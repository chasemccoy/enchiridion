import EnchiridionCore
import EnchiridionKit
import SwiftUI

/// One record, as the web's `RecordDetail` shows it, read-only with Edit for changes: the badge row (Needs curating,
/// the type, the source unless manual, the captured date, the id), the title in the serif, the byline (from the parent,
/// by the creator, at the domain), the record's images, its content as Markdown (single newlines kept as line breaks),
/// the metadata rows (Summary, URL with an open button, Published, Notes), Edit, Delete record and the Curated switch,
/// then "Linked records" grouped by predicate. In a column at most 680 pt wide, centered.
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
                    DetailContent(detail: detail, model: model, edit: edit, confirmingDelete: $confirmingDelete,
                                  titleScrolledAway: $titleScrolledAway)
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
    let edit: () -> Void
    @Binding var confirmingDelete: Bool
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
            MetadataSheet(record: record)
            ActionsRow(model: model, edit: edit, confirmingDelete: $confirmingDelete)
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

/// Summary, URL (with a button that opens it), Published and Notes, each only when the record has it.
private struct MetadataSheet: View {
    let record: Record
    @Environment(\.openURL) private var openURL

    var body: some View {
        let summary = record.summary.nonBlank
        let url = record.url.nonBlank
        let published = record.contentCreatedAt?.text(.published)
        let notes = record.notes.nonBlank
        if summary != nil || url != nil || published != nil || notes != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let summary {
                    MetadataRow("Summary", systemImage: Symbol.summary, text: summary)
                }
                if let url {
                    MetadataRow("URL", systemImage: Symbol.url) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.metaGap) {
                            Text(verbatim: url)
                                .lineLimit(3)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let link = RecordURL.web(url) {
                                Button {
                                    openURL(link)
                                } label: {
                                    Image(systemName: Symbol.openURL)
                                }
                                .buttonStyle(PressDimButtonStyle())
                                .foregroundStyle(Palette.primary)
                                .accessibilityLabel("Open source URL")
                            }
                        }
                    }
                }
                if let published {
                    MetadataRow("Published", systemImage: Symbol.published, text: published)
                }
                if let notes {
                    MetadataRow("Notes", systemImage: Symbol.notes, text: notes)
                }
            }
        }
    }
}

/// Edit and Delete record (raised buttons), then the Curated switch in `primary`. All wait while a curate or delete
/// is in flight.
private struct ActionsRow: View {
    let model: RecordDetailModel
    let edit: () -> Void
    @Binding var confirmingDelete: Bool

    var body: some View {
        FlowLayout(spacing: Space.actions, lineSpacing: Space.actionLines) {
            Button {
                edit()
            } label: {
                Label("Edit", systemImage: Symbol.edit)
            }
            .buttonStyle(.raised)
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete record", systemImage: Symbol.delete)
            }
            .buttonStyle(.raised)
            Toggle(isOn: curated) {
                Text("Curated")
                    .font(Typography.toggleLabel)
                    .foregroundStyle(Palette.text)
            }
            .toggleStyle(.switch)
            .tint(Palette.primary)
            .fixedSize()
            .padding(.leading, Space.iconGap)
        }
        .disabled(model.isWorking)
    }

    private var curated: Binding<Bool> {
        Binding {
            model.record?.isCurated ?? false
        } set: { isCurated in
            Task { await model.setCurated(isCurated) }
        }
    }
}

/// "Linked records": a group per predicate as it reads from this record ("created by", "tagged with"), its label
/// beside the rows when the column is wide and above them when it isn't (the web stacks them on narrow screens), a
/// hairline between groups. Each row opens its record.
private struct LinkedRecords: View {
    let groups: [LinkGroup]
    @State private var wide = false

    var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: Space.linked) {
                Text("Linked records")
                    .font(Typography.sectionHeading)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Palette.border.view
                            .frame(height: Metrics.formRule)
                    }
                    LinkGroupView(group: group, wide: wide)
                }
            }
            .padding(.top, Space.detailGap)
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.size.width >= Metrics.wideDetail
            } action: { isWide in
                wide = isWide
            }
        }
    }
}

private struct LinkGroupView: View {
    let group: LinkGroup
    let wide: Bool
    @ScaledMetric(relativeTo: .caption) private var labelWidth = Metrics.metadataLabelWidth

    var body: some View {
        let layout = wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Space.metaGap))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        layout {
            Text(verbatim: group.label)
                .font(Typography.groupLabel)
                .foregroundStyle(Palette.textMuted)
                .padding(.top, wide ? Metrics.linkRowPadding.top : 0)
                .frame(width: wide ? labelWidth : nil, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(group.links) { link in
                    NavigationLink(value: RecordRoute(id: link.recordID)) {
                        LinkedRecordRow(link: link)
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
            // The rows' padding hangs into the margin, so their text lines up with the label.
            .padding(.horizontal, -Metrics.linkRowPadding.leading)
        }
        .padding(.vertical, Space.badgeGap)
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
        .padding(Metrics.linkRowPadding)
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
