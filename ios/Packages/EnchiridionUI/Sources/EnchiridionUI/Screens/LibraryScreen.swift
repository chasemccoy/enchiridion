import EnchiridionCore
import EnchiridionKit
import SwiftUI

/// The library: the record cards grouped by month, with search, a filter and sort menu and New record in a Liquid Glass
/// bottom bar, and the record `LibraryModel.selectedID` names beside or above them.
///
/// On an iPhone (a compact width) it's one `NavigationStack`: the list, the selected record pushed on it, and linked
/// records pushed on that, so swiping back goes back one screen at a time. On an iPad it's a `NavigationSplitView` with
/// its own stack in the detail column.
///
/// Selection is `LibraryModel.selectedID` and nothing else, so the model's rule applies wherever the list changes:
/// curating the open record while the list shows only what needs curating opens the record that took its place. A card
/// is a button that sets `selectedID`; on an iPhone the stack's first screen follows it, and going back to the list
/// clears it, as the web's back does.
public struct LibraryScreen: View {
    @Environment(LibraryModel.self) private var library
    @State private var editor: EditorSession?

    public init() {}

    public var body: some View {
        WidthSwitch {
            StackLibrary(editor: $editor)
        } regular: {
            SplitLibrary(editor: $editor)
        }
        // Here, not in a column: a detail that finds its record deleted elsewhere closes, and the library says so
        // whichever screen is showing.
        .actionErrorAlert(library.actionError) { library.clearActionError() }
        // Every editor is presented here, above the navigation, never by a detail: a reload can move the selection
        // while one is open (the record left the list), and a sheet goes with the screen that presented it, typed
        // text and all.
        .sheet(item: $editor) { session in
            RecordEditorSheet(model: session.model) { record in
                // A new record opens; an edited one is already where it was.
                if session.model.isNew { library.selectedID = record.id }
            }
        }
        .task { await library.load() }
    }
}

/// An iPhone's library: one stack whose first pushed screen is the selected record.
private struct StackLibrary: View {
    @Environment(LibraryModel.self) private var library
    @Binding var editor: EditorSession?
    @State private var path: [RecordRoute] = []
    /// The list has been on screen. A record opened before then (a widget's or Shortcut's link at launch) waits for
    /// it: pushed over a list that was never drawn, the list's bar is laid out only on the way back, and iOS then
    /// centers the wordmark as if it were a title.
    @State private var listShown = false

    var body: some View {
        NavigationStack(path: $path) {
            LibraryList(editor: $editor)
                .onAppear {
                    guard !listShown else { return }
                    listShown = true
                    guard let selected = library.selectedID, path.isEmpty else { return }
                    // A beat after the list's first frame, so its bar exists before the record covers it.
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        if path.isEmpty, library.selectedID == selected { path = [RecordRoute(id: selected)] }
                    }
                }
                .navigationDestination(for: RecordRoute.self) { route in
                    DetailHost(id: route.id, library: library, editor: $editor) {
                        // A linked record deleted from its own screen pops it. The first screen is the selection, which
                        // the model moves to the record that took its place (and that replaces the screen below).
                        if let index = path.lastIndex(of: route), index > 0 { path.removeSubrange(index...) }
                    }
                }
        }
        .onChange(of: library.selectedID) { _, selected in
            guard let selected else {
                path = []
                return
            }
            guard listShown else { return }
            guard path.first?.id != selected else { return }
            if path.isEmpty {
                path = [RecordRoute(id: selected)]
            } else {
                // The model moved the selection (a curate or delete that took the open record out of the list): the
                // first screen becomes the new selection, under whatever linked records are open above it.
                path[0] = RecordRoute(id: selected)
            }
        }
        .onChange(of: path) { _, path in
            // Back to the list clears the selection; popping a linked record leaves it alone.
            let first = path.first?.id
            if first != library.selectedID { library.selectedID = first }
        }
    }
}

/// An iPad's library: the list beside the selected record, with a stack of its own in the detail column.
private struct SplitLibrary: View {
    @Environment(LibraryModel.self) private var library
    @Binding var editor: EditorSession?
    @State private var detailPath: [RecordRoute] = []

    var body: some View {
        NavigationSplitView {
            LibraryList(editor: $editor)
                .navigationSplitViewColumnWidth(min: Metrics.listColumnMin, ideal: Metrics.listColumnIdeal,
                                                max: Metrics.listColumnMax)
        } detail: {
            NavigationStack(path: $detailPath) {
                DetailColumn(editor: $editor)
                    .navigationDestination(for: RecordRoute.self) { route in
                        DetailHost(id: route.id, library: library, editor: $editor) {
                            if let index = detailPath.lastIndex(of: route) { detailPath.removeSubrange(index...) }
                        }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: library.selectedID) {
            // A new selection starts the detail column afresh.
            detailPath = []
        }
    }
}

// MARK: The list

private struct LibraryList: View {
    @Environment(LibraryModel.self) private var library
    @Binding var editor: EditorSession?

    var body: some View {
        @Bindable var library = library
        List {
            RefreshFailureRow()
            ForEach(library.sections) { section in
                if let heading = section.heading {
                    MonthHeader(heading)
                        .listRowInsets(EdgeInsets(
                            top: section.id == library.sections.first?.id ? Space.metaGap : Space.monthGap + Space.detailGap,
                            leading: Space.margin,
                            bottom: Space.cardGap,
                            trailing: Space.margin))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                ForEach(section.records) { record in
                    LibraryRow(record: record, endsSection: record.id == section.records.last?.id,
                               editor: $editor)
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
        .searchable(text: $library.query, prompt: Text("Search records"))
        .refreshable {
            // A refresh that answers in a blink makes the system's spinner vanish and the list stall before it
            // retracts; held for a moment, it retracts in one smooth movement, as in the system's own apps.
            async let minimum: Void? = try? Task.sleep(for: .milliseconds(700))
            await library.refresh()
            _ = await minimum
        }
        // No system title: the wordmark at the leading edge is the title.
        .navigationTitle("")
        .inlineNavigationTitle()
        .toolbar {
            // Nothing else lives up top, so the wordmark and the count share one line: no second line of title.
            ToolbarItem(placement: .leadingBarOrNavigation) {
                LibraryWordmark()
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                LibraryCount()
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .bottomBarOrAutomatic) {
                FilterMenu()
            }
            ToolbarSpacer(.fixed, placement: .bottomBarOrAutomatic)
            DefaultToolbarItem(kind: .search, placement: .bottomBarOrAutomatic)
            ToolbarSpacer(.fixed, placement: .bottomBarOrAutomatic)
            ToolbarItem(placement: .bottomBarOrAutomatic) {
                Button {
                    editor = EditorSession(model: library.newRecordEditor())
                } label: {
                    Label("New record", systemImage: Symbol.add)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

/// A failed refresh above rows still worth showing. A view of its own, so the load state changing during a refresh
/// redraws only this, never the list.
private struct RefreshFailureRow: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        if let error = library.state.error, !library.records.isEmpty {
            StatusBanner(error: error) {
                Task { await library.refresh() }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: Space.margin, bottom: Space.metaGap, trailing: Space.margin))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }
}

/// Filter and sort, in one menu: the type, Needs curation and Has media, then the order (Relevance only while
/// searching). The button's glyph fills while anything hides records, and the count under the title says how many.
private struct FilterMenu: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        @Bindable var library = library
        Menu {
            Picker(selection: $library.filters.type) {
                Label("All records", systemImage: Symbol.allRecords).tag(RecordType?.none)
                ForEach(RecordType.known, id: \.self) { type in
                    Label(type.pluralName, systemImage: type.symbolName).tag(Optional(type))
                }
            } label: {
                Text("Type")
            }
            .pickerStyle(.inline)
            Section {
                Toggle(isOn: $library.filters.needsCuration) {
                    Label("Needs curation", systemImage: Symbol.needsCuration)
                }
                Toggle(isOn: $library.filters.hasMedia) {
                    Label("Has media", systemImage: Symbol.image)
                }
            }
            Picker(selection: sort) {
                ForEach(LibraryModel.Sort.options(searching: library.isSearching), id: \.self) { sort in
                    Text(verbatim: sort.title).tag(sort)
                }
            } label: {
                Label("Sort by", systemImage: Symbol.sort)
                Text(verbatim: library.filters.effectiveSort(searching: library.isSearching).title)
            }
            .pickerStyle(.menu)
            if library.filters != LibraryModel.Filters() {
                Section {
                    Button(role: .destructive) {
                        library.filters = LibraryModel.Filters()
                    } label: {
                        Label("Reset filters", systemImage: Symbol.reset)
                    }
                }
            }
        } label: {
            Label("Filter and sort", systemImage: library.filters.isActive ? Symbol.filterOn : Symbol.filter)
        }
        .keepsMenuOpen()
    }

    /// The order as the menu shows it: the one in effect, so the default reads as checked.
    private var sort: Binding<LibraryModel.Sort> {
        Binding {
            library.filters.effectiveSort(searching: library.isSearching)
        } set: { sort in
            library.filters.sort = sort
        }
    }
}

/// One row: a button that selects it, with the swipe actions, the context menu and the delete confirmation (anchored
/// here, so on iPad it points at the row). Edge to edge, `elevated` while pressed and while selected (iPad), with the
/// list's hairline below it inset to the text. VoiceOver offers the swipe actions as the row's actions.
private struct LibraryRow: View {
    let record: ListRecord
    /// The month's (or the search results') last row: no hairline under it, so the gap before the next month reads
    /// as the break.
    var endsSection = false
    @Binding var editor: EditorSession?
    @Environment(LibraryModel.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var confirmingDelete = false

    /// A curate or delete is in flight: the row dims, and takes no other action until it's done.
    private var isWorking: Bool { library.workingIDs.contains(record.id) }

    var body: some View {
        let isSelected = library.selectedID == record.id
        let link = RecordURL.web(record.url)
        Button {
            library.selectedID = record.id
        } label: {
            RecordRow(record, showsParent: library.isSearching)
                .padding(Metrics.rowPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .opacity(isWorking ? 0.6 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenuPreviewShape(Rectangle())
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
                editor = EditorSession(model: library.editor(for: record))
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
        .listRowInsets(EdgeInsets())
        // A hairline only between two rows: each row draws the one below it unless it ends its month (or the
        // results), and none draws above itself, so nothing sits over the first row or above a month heading. Set
        // per edge: a modifier for all edges would win over the per-edge one, as the nearer one does.
        .listRowSeparator(.hidden, edges: .top)
        .listRowSeparator(endsSection ? .hidden : .visible, edges: .bottom)
        .listRowSeparatorTint(Palette.border.color)
        .alignmentGuide(.listRowSeparatorLeading) { _ in Metrics.rowPadding.leading }
        .listRowBackground((isSelected ? Palette.elevated : Palette.page).view)
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

/// The serif wordmark, at the bar's leading edge.
private struct LibraryWordmark: View {
    var body: some View {
        Text("Enchiridion")
            .font(Typography.wordmark)
            .foregroundStyle(Palette.text)
            .lineLimit(1)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}

/// The count at the bar's trailing edge, in the web's words ("567 records", "12 of 567 records", "8 results",
/// "Searching…"); a failed search's count reads in `error`. Nothing until an index has loaded.
private struct LibraryCount: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        if let count = library.countText {
            let searchFailed = library.isSearching && library.searchState.error != nil
            Text(verbatim: count)
                .font(Typography.count)
                .monospacedDigit()
                .foregroundStyle(searchFailed ? Palette.error : Palette.textDimmed)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
                .animation(.default, value: count)
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
    @Binding var editor: EditorSession?

    var body: some View {
        if let id = library.selectedID {
            DetailHost(id: id, library: library, editor: $editor, onDeleted: nil)
                .id(id)
        } else {
            EmptyMessage(title: "No record open", message: "Choose one from the list.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.page)
        }
    }
}

/// Owns one record's `RecordDetailModel` (made by the library, so its saves and deletes reach the rows) and shows it.
/// Its Edit opens in the library's editor sheet.
private struct DetailHost: View {
    let id: Int
    @Binding var editor: EditorSession?
    let onDeleted: (() -> Void)?
    @State private var model: RecordDetailModel

    /// The model is made here, once per screen: `@State` keeps the first and drops the ones later inits make.
    init(id: Int, library: LibraryModel, editor: Binding<EditorSession?>, onDeleted: (() -> Void)?) {
        self.id = id
        _editor = editor
        self.onDeleted = onDeleted
        _model = State(initialValue: library.detailModel(id: id))
    }

    var body: some View {
        RecordDetailScreen(model: model, onDeleted: onDeleted) { editorModel in
            editor = EditorSession(model: editorModel)
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
        .previewRoot()
}
#endif
