import EnchiridionCore
import EnchiridionKit
import struct EnchiridionKit.Predicate
import SwiftUI

/// The share extension's card: the web's add form (the page the browser extension opens), filled from the share. A
/// column on the page color: a preview row (the domain, then the page's title as shared, else its path; or "Text" for
/// a text share), the title in the serif (focused on open), the type (segmented), the content (the selection or shared
/// text), Details (summary, link, notes), Curated, and Links, then "Save to Enchiridion". Cancel sits in the bar.
///
/// "Add link" is the web's two-step picker, pushed on the card's stack: search for a record, then say how it's linked.
/// A pending link's relationship can be changed from its menu, or the link removed. Links are added once the record
/// has saved (`ShareComposeModel.save()`).
///
/// The endings follow `ShareComposeModel.state`:
/// - **Saving:** the fields wait and the button reads "Saving…".
/// - **Saved:** the card crossfades to "Saved to Enchiridion", and `onDone` runs after `savedLinger` (the extension
///   completes its request). A save whose links didn't all go stays open instead: the record is in, the links that
///   failed are named, with Retry (`retryLinks()`) and Done.
/// - **Failed:** the error's message (the not-allowed state for a 401 that names this device), with Retry and Copy
///   link (Copy text for a text share), so nothing shared is lost. Retry looks up the slug of a create whose answer was
///   lost before trying again, so it never makes a second record; such a failure reads "Couldn't confirm it saved",
///   not "Not saved", since the record may be there already.
///
/// It sets its own tint and root styles: an extension's views live in the host app's window and get none of this
/// bundle's.
public struct ShareComposeView: View {
    let model: ShareComposeModel
    let onDone: () -> Void
    let onCancel: () -> Void
    let savedLinger: Duration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: Field?
    @State private var path: [LinkPickerStep] = []
    @State private var search: RecordSearchModel?

    private enum Field: Hashable {
        case title, content, summary, url, note
    }

    /// `onDone` runs once the saved ending has shown for `savedLinger`; `onCancel` when Cancel is tapped (without it,
    /// Cancel calls `onDone`).
    public init(model: ShareComposeModel, onDone: @escaping () -> Void, onCancel: (() -> Void)? = nil,
                savedLinger: Duration = Timings.standard.savedLinger) {
        self.model = model
        self.onDone = onDone
        self.onCancel = onCancel ?? onDone
        self.savedLinger = savedLinger
    }

    /// Saved with every link: the ending shows, then the card closes.
    private var finished: Bool {
        model.state.savedRecord != nil && model.failedLinks.isEmpty
    }

    public var body: some View {
        let saved = model.state.savedRecord != nil
        NavigationStack(path: $path) {
            Group {
                if finished {
                    SavedEnding()
                        .transition(.opacity)
                } else if saved {
                    LinksFailedEnding(model: model, onDone: onDone)
                        .transition(.opacity)
                } else {
                    ScrollView {
                        composing
                            .frame(maxWidth: Metrics.shareCardWidth)
                            .padding(.horizontal, Space.margin)
                            .padding(.vertical, Space.metaGap)
                            .frame(maxWidth: .infinity)
                    }
                    .dismissesKeyboardInteractively()
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.page)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Enchiridion")
                        .font(Typography.wordmark)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
                if !saved {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { onCancel() }
                            .disabled(model.state.isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) { save() }
                            .disabled(!model.canSave)
                    }
                }
            }
            .inlineNavigationTitle()
            .navigationDestination(for: LinkPickerStep.self) { step in
                switch step {
                case .record:
                    if let search {
                        RecordLinkSearch(search: search, path: $path)
                    }
                case .predicate(let row):
                    LinkPredicatePicker(target: row) { predicate in
                        model.draft.link(PendingLink(row, predicate: predicate))
                        path = []
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: saved)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: finished)
        .enchiridionRoot()
        .onAppear { focus = .title }
        .onChange(of: finished) { _, finished in
            guard finished else { return }
            AccessibilityNotification.Announcement("Saved to Enchiridion").post()
            Task {
                try? await Task.sleep(for: savedLinger)
                onDone()
            }
        }
    }

    private var composing: some View {
        @Bindable var model = model
        let saving = model.state.isSaving
        return VStack(alignment: .leading, spacing: Space.formSection) {
            SharePreview(model: model)
            VStack(alignment: .leading, spacing: Space.formSection) {
                TextField("Title", text: $model.draft.title, prompt: prompt("Untitled record"), axis: .vertical)
                    .font(Typography.detailTitle)
                    .lineSpacing(Typography.detailTitleLineSpacing)
                    .foregroundStyle(Palette.textHighlighted)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 4)
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    // The field wraps a long title, but a title is one line: Return moves on to the content.
                    .onChange(of: model.draft.title) { _, title in
                        guard title.contains(where: \.isNewline) else { return }
                        model.draft.title = title.split(whereSeparator: \.isNewline).joined(separator: " ")
                        focus = .content
                    }
                Picker("Type", selection: $model.draft.type) {
                    ForEach([RecordType.artifact, .concept, .entity], id: \.self) { type in
                        Text(verbatim: type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                FormSection("Content") {
                    TextField("Content", text: text($model.draft.selection),
                              prompt: prompt("Write something about this record"), axis: .vertical)
                        .lineLimit(3 ... 12)
                        .focused($focus, equals: .content)
                }
                FormSection("Details") {
                    DetailField(symbol: Symbol.summary, label: "Summary") {
                        TextField("Summary", text: text($model.draft.summary),
                                  prompt: prompt("A brief summary"), axis: .vertical)
                            .lineLimit(1 ... 6)
                            .focused($focus, equals: .summary)
                    }
                    DetailField(symbol: Symbol.url, label: "Link") {
                        TextField("Link", text: text($model.draft.url), prompt: prompt("example.com"))
                            .urlEntry()
                            .focused($focus, equals: .url)
                            .submitLabel(.next)
                            .onSubmit { focus = .note }
                    }
                    DetailField(symbol: Symbol.notes, label: "Notes") {
                        TextField("Notes", text: $model.draft.note, prompt: prompt("Additional notes"),
                                  axis: .vertical)
                            .lineLimit(1 ... 8)
                            .focused($focus, equals: .note)
                    }
                    Toggle("Curated", isOn: $model.draft.isCurated)
                        .font(Typography.toggleLabel)
                        .tint(Palette.primary)
                }
                PendingLinks(draft: $model.draft) {
                    focus = nil
                    if search == nil { search = model.makeSearch() }
                    path = [.record]
                }
            }
            .disabled(saving)
            if let error = model.state.error {
                ShareFailure(error: error, model: model)
            }
            Button {
                save()
            } label: {
                Text(saving ? "Saving…" : model.state.error == nil ? "Save to Enchiridion" : "Retry")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonSizing(.flexible)
            .disabled(!model.canSave)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(verbatim: text).foregroundStyle(Palette.textDimmed)
    }

    /// An optional field as a text field's string: blank reads as nil.
    private func text(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func save() {
        guard model.canSave else { return }
        focus = nil
        Task { await model.save() }
    }
}

/// A labelled field in Details: the label (with its symbol) small and muted above the field.
private struct DetailField<Field: View>: View {
    let symbol: String
    let label: String
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: Space.iconGap) {
            Label(label, systemImage: symbol)
                .font(Typography.metadataLabel)
                .foregroundStyle(Palette.textMuted)
                .accessibilityHidden(true)
            field()
        }
    }
}

/// The links the record will get: each target with its relationship (a menu to change it) and a remove button, then
/// "Add link".
private struct PendingLinks: View {
    @Binding var draft: ShareDraft
    let add: () -> Void

    var body: some View {
        FormSection("Links") {
            ForEach(draft.links) { link in
                HStack(spacing: Space.metaGap) {
                    VStack(alignment: .leading, spacing: Space.metaLineGap) {
                        Menu {
                            Picker("Relationship", selection: predicate(of: link)) {
                                ForEach(Predicate.linkOptions, id: \.self) { predicate in
                                    Text(verbatim: predicate.menuName).tag(predicate)
                                }
                            }
                        } label: {
                            HStack(spacing: Space.iconGap) {
                                Text(verbatim: link.predicate.menuName)
                                Image(systemName: Symbol.relationship)
                                    .imageScale(.small)
                            }
                            .font(Typography.metadataLabel)
                            .foregroundStyle(Palette.textMuted)
                        }
                        .accessibilityLabel(Text(verbatim: "Relationship: \(link.predicate.menuName)"))
                        LinkTargetRow(title: link.title, slug: link.slug, type: link.type)
                    }
                    Button(role: .destructive) {
                        draft.links.removeAll { $0.id == link.id }
                    } label: {
                        Image(systemName: Symbol.removeLink)
                            .foregroundStyle(Palette.textDimmed)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: "Remove link to \(link.displayTitle)"))
                }
            }
            Button(action: add) {
                Label("Add link", systemImage: Symbol.add)
                    .font(Typography.toggleLabel)
                    .foregroundStyle(Palette.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func predicate(of link: PendingLink) -> Binding<Predicate> {
        Binding(get: { link.predicate }, set: { predicate in
            var changed = link
            changed.predicate = predicate
            draft.link(changed)
        })
    }
}

/// The record saved but some links didn't: which, with Retry and Done.
private struct LinksFailedEnding: View {
    let model: ShareComposeModel
    let onDone: () -> Void
    @State private var retrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.detailGap) {
            Label("Saved, but some links weren't added", systemImage: Symbol.failure)
                .font(Typography.stateTitle)
                .foregroundStyle(Palette.textHighlighted)
            Text(verbatim: model.failedLinks.map { "\($0.predicate.menuName) \($0.displayTitle)" }
                .joined(separator: "\n"))
                .font(Typography.stateMessage)
                .foregroundStyle(Palette.textMuted)
                .wrapsFully()
            HStack(spacing: Space.actions) {
                Button("Done", action: onDone)
                    .buttonStyle(.bordered)
                Button(retrying ? "Retrying…" : "Retry") {
                    retrying = true
                    Task {
                        await model.retryLinks()
                        retrying = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(retrying)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: Metrics.shareCardWidth, alignment: .leading)
        .padding(Space.margin)
        .frame(maxWidth: .infinity)
    }
}

/// What is shared: a page's domain, then its title as the page gave it (else its path); or "Text" for a text share.
private struct SharePreview: View {
    let model: ShareComposeModel
    @ScaledMetric(relativeTo: .body) private var iconSize = Metrics.sharePreviewIcon

    var body: some View {
        HStack(alignment: .center, spacing: Space.cardPadding) {
            Image(systemName: model.domain == nil ? Symbol.text : Symbol.page)
                .font(Typography.count.weight(.semibold))
                .foregroundStyle(Palette.textMuted)
                .frame(width: iconSize, height: iconSize)
                .background(Palette.elevated, in: Radius.shape(Radius.button))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.domain ?? "Text")
                    .font(Typography.shareDomain)
                    .foregroundStyle(Palette.textHighlighted)
                    .lineLimit(1)
                if let detail {
                    Text(verbatim: detail)
                        .font(Typography.stateMessage)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The page's own title, else its path (a bare "/" counts as none).
    private var detail: String? {
        if let title = model.input.title.nonBlank {
            return title.split(whereSeparator: \.isNewline).joined(separator: " ")
        }
        guard let path = model.input.url?.path(percentEncoded: false), path != "/", !path.isEmpty else { return nil }
        return path
    }
}

/// A save that failed: why, and Copy link so the page isn't lost (Retry is the main button). A save whose record may
/// exist all the same (its answer lost, `mayHaveSaved`) says it couldn't be confirmed, not that it wasn't saved: Retry
/// finds that record, while sharing again later from a new card would save it twice.
private struct ShareFailure: View {
    let error: EnchiridionError
    let model: ShareComposeModel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.metaGap) {
            if case .unauthorized(let device?) = error {
                NotAllowedView(device: device, compact: true)
            } else {
                Label(model.mayHaveSaved ? "Couldn't confirm it saved" : "Not saved", systemImage: Symbol.failure)
                    .font(Typography.stateMessage.weight(.semibold))
                    .foregroundStyle(Palette.error)
                Text(verbatim: model.mayHaveSaved
                    ? "\(error.message) It may be in Enchiridion already. Retry checks first, so it won't save twice."
                    : error.message)
                    .font(Typography.stateMessage)
                    .foregroundStyle(Palette.text)
                    .wrapsFully()
            }
            if let copyable {
                Button {
                    Pasteboard.copy(copyable.text)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : copyable.label, systemImage: Symbol.copy)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.elevated, in: Radius.shape(Radius.card))
        .accessibilityElement(children: .contain)
    }

    /// The link for a page, else the shared text.
    private var copyable: (label: String, text: String)? {
        if let url = model.input.url { return ("Copy link", url.absoluteString) }
        if let text = model.draft.selection.nonBlank { return ("Copy text", text) }
        return nil
    }
}

/// "Saved to Enchiridion", with a check in `primary`.
private struct SavedEnding: View {
    var body: some View {
        VStack(spacing: Space.metaGap) {
            Image(systemName: Symbol.saved)
                .font(.largeTitle)
                .foregroundStyle(Palette.primary)
                .accessibilityHidden(true)
            Text("Saved to Enchiridion")
                .font(Typography.stateTitle)
                .foregroundStyle(Palette.textHighlighted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.monthGap)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A text field drawn as the web's input: `surface`, a `border` hairline, the button radius.
    fileprivate func boxedField() -> some View {
        let shape = Radius.shape(Radius.button)
        return textFieldStyle(.plain)
            .font(Typography.field)
            .foregroundStyle(Palette.text)
            .padding(Metrics.fieldPadding)
            .background(Palette.surface, in: shape)
            .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
    }
}

#if DEBUG
#Preview("Share a page") {
    ShareComposeView(
        model: ShareComposeModel(
            input: ShareInput(
                url: URL(string: "https://www.sqlite.org/whentouse.html"),
                title: "Appropriate uses for SQLite",
                selection: "SQLite does not compete with client/server databases. SQLite competes with fopen().",
                summary: "Situations where SQLite works well, and where a client/server database is better."),
            environment: .preview()),
        onDone: {})
        .previewRoot()
}

#Preview("Share, not on the list") {
    ShareComposeView(
        model: ShareComposeModel(input: ShareInput(text: "A thought worth keeping."),
                                 environment: .preview(.notAllowed)),
        onDone: {})
        .previewRoot()
}
#endif
