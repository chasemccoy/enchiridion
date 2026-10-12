import EnchiridionCore
import EnchiridionKit
import struct EnchiridionKit.Predicate
import SwiftUI

/// A step of adding a link, pushed on the presenting stack: find the record, then say how it's linked (the web's
/// two-step "Add link" popover).
enum LinkPickerStep: Hashable {
    case record
    case predicate(ListRecord)
}

/// "Add link", step one: search for the record to link to. Results come from hybrid search as you type; picking one
/// pushes \`LinkPredicatePicker\`.
struct RecordLinkSearch: View {
    let search: RecordSearchModel
    @Binding var path: [LinkPickerStep]

    var body: some View {
        @Bindable var search = search
        List {
            ForEach(search.results) { row in
                Button {
                    path.append(.predicate(row))
                } label: {
                    LinkTargetRow(title: row.title, slug: row.slug, type: row.type)
                }
                .listRowBackground(Palette.surface.view)
            }
        }
        .groupedList()
        .scrollContentBackground(.hidden)
        .background(Palette.page)
        .overlay {
            if search.results.isEmpty {
                Group {
                    if search.isSearching {
                        LoadingIndicator(label: "Searching")
                    } else if let error = search.error {
                        EmptyMessage(title: "Search failed", message: error.message)
                    } else if search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                        EmptyMessage(title: "Find a record", message: "Search by title, author, tag or text.")
                    } else {
                        EmptyMessage(title: "No results", message: "Nothing matches “\(search.query)”.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alwaysVisibleSearch(text: $search.query, prompt: "Search for a record to link")
        .navigationTitle("Add link")
        .inlineNavigationTitle()
    }
}

/// "Add link", step two: how the new record relates to the one picked ("Created by", "Tagged with"…). Picking one
/// adds the link and returns to the form.
struct LinkPredicatePicker: View {
    let target: ListRecord
    let choose: (Predicate) -> Void

    var body: some View {
        List {
            Section {
                LinkTargetRow(title: target.title, slug: target.slug, type: target.type)
                    .listRowBackground(Palette.surface.view)
            } header: {
                Text("Linking to")
            }
            Section {
                ForEach(Predicate.linkOptions, id: \.self) { predicate in
                    Button {
                        choose(predicate)
                    } label: {
                        Text(verbatim: predicate.menuName)
                            .font(Typography.linkTitle)
                            .foregroundStyle(Palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .listRowBackground(Palette.surface.view)
                }
            } header: {
                Text("This record is…")
            }
        }
        .groupedList()
        .scrollContentBackground(.hidden)
        .background(Palette.page)
        .navigationTitle("How is it linked?")
        .inlineNavigationTitle()
    }
}

/// A record in a pick list: its type's symbol, then its title (else its slug).
struct LinkTargetRow: View {
    let title: String?
    let slug: String
    let type: RecordType

    var body: some View {
        HStack(spacing: Space.metaGap) {
            Image(systemName: type.symbolName)
                .font(Typography.count)
                .foregroundStyle(Palette.textDimmed)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(verbatim: title.nonBlank ?? slug)
                .font(Typography.linkTitle)
                .foregroundStyle(Palette.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(title.nonBlank ?? slug), \(type.displayName)"))
    }
}
