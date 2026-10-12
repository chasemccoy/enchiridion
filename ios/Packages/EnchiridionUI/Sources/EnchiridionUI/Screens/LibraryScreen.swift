import EnchiridionCore
import EnchiridionKit
import SwiftUI

/// The library: a `NavigationSplitView` whose list column holds the record cards and whose detail column shows the
/// record `LibraryModel.selectedID` names. Reads `LibraryModel` from the environment (`EnchiridionRootView` puts it
/// there).
///
/// The list column: the serif wordmark with the record count under it; Settings and New record in the bar; a filter bar
/// (All, Artifact, Concept, Entity, then Needs curation); search ("Search records", hybrid search after a pause);
/// cards grouped by month, the selected one ringed in `primary`; pull to refresh; swipe right to curate, left to
/// delete; a context menu with Open link, Copy link, Curate, Edit and Delete.
///
/// Selection is `LibraryModel.selectedID` and nothing else, so the model's rule applies wherever the list changes:
/// curating the open record while the list shows only what needs curating opens the record that took its place. The
/// list is not a selection list: a card is a button that sets `selectedID`, and the split view's compact column follows
/// it (`preferredCompactColumn`), so the ring is the only selection mark, without the system's row highlight under it.
public struct LibraryScreen: View {
    @Environment(LibraryModel.self) private var library
    @State private var sheet: LibrarySheet?
    @State private var detailPath: [RecordRoute] = []
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar

    public init() {}

    public var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            LibraryList(sheet: $sheet)
                .navigationSplitViewColumnWidth(min: Metrics.listColumnMin, ideal: Metrics.listColumnIdeal,
                                                max: Metrics.listColumnMax)
        } detail: {
            NavigationStack(path: $detailPath) {
                DetailColumn(sheet: $sheet)
                    .navigationDestination(for: RecordRoute.self) { route in
                        DetailHost(id: route.id, library: library, sheet: $sheet) {
                            if let index = detailPath.lastIndex(of: route) { detailPath.removeSubrange(index...) }
                        }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: library.selectedID) { _, selected in
            // A new selection starts the detail column afresh; on a phone it opens the detail, and a selection that
            // went away (the list emptied) goes back to the list.
            detailPath = []
            compactColumn = selected == nil ? .sidebar : .detail
        }
        .onChange(of: compactColumn) { _, column in
            // Only collapsed navigation moves this binding: back to the list on a phone deselects, as the web does.
            if column == .sidebar, library.selectedID != nil { library.selectedID = nil }
        }
        // On the split view, not a column: a detail that finds its record deleted elsewhere closes, and the library
        // says so here whichever column is showing.
        .actionErrorAlert(library.actionError) { library.clearActionError() }
        .sheet(item: $sheet) { presented in
            switch presented {
            case .settings:
                SettingsSheet()
            case .editor(let session):
                RecordEditorSheet(model: session.model) { record in
                    // A new record opens; an edited one is already where it was.
                    if session.model.isNew { library.selectedID = record.id }
                }
            }
        }
        .task { await library.load() }
    }
}

/// What the library presents: Settings or an editor (New record, a card's Edit, or a detail's Edit). Every editor is
/// presented here, above the split view, never by a detail: a reload can move the selection while one is open (the
/// record left the list), and a sheet goes with the screen that presented it, typed text and all.
enum LibrarySheet: Identifiable {
    case settings
    case editor(EditorSession)

    var id: AnyHashable {
        switch self {
        case .settings: AnyHashable("settings")
        case .editor(let session): AnyHashable(session.id)
        }
    }
}

// MARK: The list column

private struct LibraryList: View {
    @Environment(LibraryModel.self) private var library
    @Binding var sheet: LibrarySheet?

    var body: some View {
        @Bindable var library = library
        List {
            ForEach(library.sections) { section in
                if let heading = section.heading {
                    MonthHeader(heading)
                        .listRowInsets(EdgeInsets(
                            top: section.id == library.sections.first?.id ? 0 : Space.monthGap - Space.cardGap / 2,
                            leading: Space.margin,
                            bottom: Space.afterMonthHeader - Space.cardGap / 2,
                            trailing: Space.margin))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                ForEach(section.records) { record in
                    LibraryRow(record: record, sheet: $sheet)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, Space.metaGap, for: .scrollContent)
        .contentMargins(.bottom, Space.monthGap, for: .scrollContent)
        .background(Palette.page)
        .overlay { LibraryPlaceholder() }
        .safeAreaBar(edge: .top, spacing: 0) {
            LibraryBar()
        }
        .searchable(text: $library.query, prompt: Text("Search records"))
        .refreshable { await library.refresh() }
        .navigationTitle("Enchiridion")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .principal) {
                LibraryTitle()
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .navigation) {
                Button {
                    sheet = .settings
                } label: {
                    Label("Settings", systemImage: Symbol.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sheet = .editor(EditorSession(model: library.newRecordEditor()))
                } label: {
                    Label("New record", systemImage: Symbol.add)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

/// One card: a button that selects it, with the swipe actions, the context menu and the delete confirmation (anchored
/// here, so on iPad it points at the card). VoiceOver offers the swipe actions as the card's actions.
private struct LibraryRow: View {
    let record: ListRecord
    @Binding var sheet: LibrarySheet?
    @Environment(LibraryModel.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var confirmingDelete = false

    /// A curate or delete is in flight: the card dims, and takes no other action until it's done.
    private var isWorking: Bool { library.workingIDs.contains(record.id) }

    var body: some View {
        let isSelected = library.selectedID == record.id
        let link = RecordURL.web(record.url)
        Button {
            library.selectedID = record.id
        } label: {
            RecordCard(record, isSelected: isSelected, showsParent: library.isSearching)
        }
        .buttonStyle(PressDimButtonStyle())
        .opacity(isWorking ? 0.6 : 1)
        .contextMenuPreviewShape(Radius.shape(Radius.card))
        .contextMenu {
            if let link {
                Button {
                    openURL(link)
                } label: {
                    Label("Open link", systemImage: Symbol.openURL)
                }
                Button {
                    Pasteboard.copy(record.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? link.absoluteString)
                } label: {
                    Label("Copy link", systemImage: Symbol.copy)
                }
            }
            curateButton
            Button {
                sheet = .editor(EditorSession(model: library.editor(for: record)))
            } label: {
                Label("Edit", systemImage: Symbol.edit)
            }
            .disabled(isWorking)
            Divider()
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: Symbol.delete)
            }
            .disabled(isWorking)
        }
        .listRowInsets(EdgeInsets(top: Space.cardGap / 2, leading: Space.margin, bottom: Space.cardGap / 2,
                                  trailing: Space.margin))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            curateButton
                .tint(Palette.primary.color)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Not a destructive-role button: that one removes the row at once, before the confirmation is answered.
            Button {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: Symbol.delete)
            }
            .tint(Palette.error.color)
            .disabled(isWorking)
        }
        .confirmationDialog("Delete this record?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete record", role: .destructive) {
                Task { await library.delete(id: record.id) }
            }
        } message: {
            Text(verbatim: RecordName.deletion(record.title))
        }
    }

    private var curateButton: some View {
        Button {
            Task { await library.setCurated(id: record.id, !record.isCurated) }
        } label: {
            if record.isCurated {
                Label("Uncurate", systemImage: Symbol.uncurate)
            } else {
                Label("Curate", systemImage: Symbol.curate)
            }
        }
        .disabled(isWorking)
    }
}

/// The wordmark, with the count under it in the web's words ("567 records", "12 of 567 records", "8 results",
/// "Searching…"); a failed search's count reads in `error`. No count until an index has loaded.
private struct LibraryTitle: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        let searchFailed = library.isSearching && library.searchState.error != nil
        VStack(spacing: 0) {
            Text("Enchiridion")
                .font(Typography.wordmark)
                .foregroundStyle(Palette.text)
            if let count = library.countText {
                Text(verbatim: count)
                    .font(Typography.count)
                    .monospacedDigit()
                    .foregroundStyle(searchFailed ? Palette.error : Palette.textDimmed)
                    .contentTransition(.numericText())
                    .animation(.default, value: count)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The filter chips, and below them a failed refresh when there are records to show anyway. The row scrolls sideways
/// on a narrow phone; a chip turned on scrolls fully into view, so a selected filter is never cut off at the edge.
private struct LibraryBar: View {
    @Environment(LibraryModel.self) private var library

    /// The chips' scroll ids.
    private enum Chip: Hashable {
        case all
        case type(RecordType)
        case needsCuration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.metaGap) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: Space.chipGap) {
                        FilterChip("All", isSelected: library.filters.type == nil) {
                            library.filters.type = nil
                        }
                        .id(Chip.all)
                        ForEach(RecordType.known, id: \.self) { type in
                            FilterChip(type: type, isSelected: library.filters.type == type) {
                                // A selected type's chip turns its filter off, as the web's toggles do.
                                library.filters.type = library.filters.type == type ? nil : type
                            }
                            .id(Chip.type(type))
                        }
                        Palette.border.view
                            .frame(width: Metrics.filterDivider.width, height: Metrics.filterDivider.height)
                            .padding(.horizontal, Space.iconGap)
                            .accessibilityHidden(true)
                        FilterChip("Needs curation", systemImage: Symbol.needsCuration,
                                   isSelected: library.filters.needsCuration) {
                            library.filters.needsCuration.toggle()
                        }
                        .id(Chip.needsCuration)
                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.vertical, Metrics.filterBarPadding)
                }
                .scrollIndicators(.hidden)
                .onChange(of: library.filters) { old, new in
                    let turnedOn: Chip? = if new.needsCuration, !old.needsCuration {
                        .needsCuration
                    } else if let type = new.type, type != old.type {
                        .type(type)
                    } else {
                        nil
                    }
                    guard let turnedOn else { return }
                    withAnimation { proxy.scrollTo(turnedOn) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filters")

            if let error = library.state.error, !library.records.isEmpty {
                StatusBanner(error: error) {
                    Task { await library.refresh() }
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.metaGap)
            }
        }
    }
}

/// What the list shows when it has no cards: loading, a failed load (the not-allowed state for a 401 that names this
/// device), an empty library, no search results, or filters that hide everything.
private struct LibraryPlaceholder: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        if library.visibleRecords.isEmpty {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var content: some View {
        if library.isSearching {
            if let error = library.searchState.error, library.searchResults == nil {
                ErrorState(error) { retry() }
            } else if library.searchResults == nil || library.searchState.isLoading {
                LoadingIndicator(label: "Searching")
            } else if library.searchResults?.isEmpty == false {
                filteredOut(noun: "results")
            } else {
                EmptyMessage(title: "No results", message: "Nothing matches “\(library.activeQuery)”.")
            }
        } else if library.records.isEmpty {
            if let error = library.state.error {
                ErrorState(error) { retry() }
            } else if library.state == .loaded {
                EmptyMessage(title: "No records yet",
                             message: "Add one with New record, on the web, or from the share sheet.")
            } else {
                LoadingIndicator(label: "Loading records")
            }
        } else {
            filteredOut(noun: "records")
        }
    }

    private func filteredOut(noun: String) -> some View {
        let onlyCuration = library.filters.needsCuration && library.filters.type == nil
        return EmptyMessage(title: onlyCuration ? "Nothing needs curating" : "No matching \(noun)",
                            message: onlyCuration ? "Everything here is curated." : "The filters hide everything here.",
                            action: ("Show all", { library.filters = LibraryModel.Filters() }))
    }

    private func retry() {
        Task { await library.refresh() }
    }
}

// MARK: The detail column

/// The selected record, or a note to pick one. A new selection is a new screen (`.id`), with its own model.
private struct DetailColumn: View {
    @Environment(LibraryModel.self) private var library
    @Binding var sheet: LibrarySheet?

    var body: some View {
        if let id = library.selectedID {
            DetailHost(id: id, library: library, sheet: $sheet, onDeleted: nil)
                .id(id)
        } else {
            EmptyMessage(title: "No record open", message: "Choose one from the list.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.page)
        }
    }
}

/// Owns one record's `RecordDetailModel` (made by the library, so its saves and deletes reach the rows) and shows it.
/// Its Edit opens in the library's `sheet` (`LibrarySheet`).
private struct DetailHost: View {
    let id: Int
    @Binding var sheet: LibrarySheet?
    let onDeleted: (() -> Void)?
    @State private var model: RecordDetailModel

    /// The model is made here, once per screen: `@State` keeps the first and drops the ones later inits make.
    init(id: Int, library: LibraryModel, sheet: Binding<LibrarySheet?>, onDeleted: (() -> Void)?) {
        self.id = id
        _sheet = sheet
        self.onDeleted = onDeleted
        _model = State(initialValue: library.detailModel(id: id))
    }

    var body: some View {
        RecordDetailScreen(model: model, onDeleted: onDeleted) { editor in
            sheet = .editor(EditorSession(model: editor))
        }
        .background { RowSync(id: id, model: model) }
    }
}

/// Keeps an open detail in step with changes made from the list (a swipe to curate, a context menu's Edit, a pull to
/// refresh): it reports the row to the detail, which reloads once the row has settled and is ahead of it, waiting out
/// a load or curate of its own (`RecordDetailModel.rowChanged(_:)`). A view of its own, so the library's changes
/// re-render only this and never the detail's content.
private struct RowSync: View {
    let id: Int
    let model: RecordDetailModel
    @Environment(LibraryModel.self) private var library

    var body: some View {
        let state = library.row(id: id).map { row in
            RecordDetailModel.RowState(isCurated: row.isCurated, updatedAt: row.recordUpdatedAt,
                                       working: library.workingIDs.contains(id))
        }
        Color.clear
            .onChange(of: state) { _, state in
                model.rowChanged(state)
            }
    }
}

#if DEBUG
#Preview("Library") {
    LibraryScreen()
        .environment(LibraryModel(environment: .preview()))
        .environment(ConnectionModel(environment: .preview()))
        .previewRoot()
}
#endif
