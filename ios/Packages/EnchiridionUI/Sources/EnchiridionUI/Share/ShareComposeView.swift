import EnchiridionCore
import EnchiridionKit
import SwiftUI

/// The share extension's card: saves what was shared as a new artifact record. A compact column on the page color:
/// a preview row (the domain, then the page's title as shared, else its path; or "Text" for a text share), the editable
/// title, an "Add a note" field (3 to 8 lines, focused on open), the selection as a quote (3 lines), and "Save to
/// Enchiridion". Cancel sits in the bar.
///
/// The endings follow `ShareComposeModel.state`:
/// - **Saving:** the fields wait and the button reads "Saving…".
/// - **Saved:** the card crossfades to "Saved to Enchiridion", and `onDone` runs after `savedLinger` (the extension
///   completes its request).
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

    private enum Field: Hashable {
        case title, note
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

    public var body: some View {
        let saved = model.state.savedRecord != nil
        NavigationStack {
            Group {
                if saved {
                    SavedEnding()
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
                }
            }
            .inlineNavigationTitle()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: saved)
        .enchiridionRoot()
        .onAppear { focus = .note }
        .onChange(of: saved) { _, saved in
            guard saved else { return }
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
        return VStack(alignment: .leading, spacing: Space.detailGap) {
            SharePreview(model: model)
            VStack(alignment: .leading, spacing: Space.metaGap) {
                TextField("Title", text: $model.draft.title, prompt: prompt("Title"), axis: .vertical)
                    .lineLimit(1 ... 3)
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focus = .note }
                    // The field wraps a long title, but a title is one line: Return moves on to the note.
                    .onChange(of: model.draft.title) { _, title in
                        guard title.contains(where: \.isNewline) else { return }
                        model.draft.title = title.split(whereSeparator: \.isNewline).joined(separator: " ")
                        focus = .note
                    }
                    .boxedField()
                TextField("Add a note", text: $model.draft.note, prompt: prompt("Add a note"), axis: .vertical)
                    .lineLimit(3 ... 8)
                    .focused($focus, equals: .note)
                    .boxedField()
            }
            .disabled(saving)
            if let selection = model.draft.selection.nonBlank {
                SelectionQuote(text: selection)
            }
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

    private func save() {
        guard model.canSave else { return }
        focus = nil
        Task { await model.save() }
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

/// The selection, three lines of it, behind a quote rule.
private struct SelectionQuote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.quoteGap) {
            Palette.borderAccented.view
                .frame(width: Metrics.quoteRule)
            Text(verbatim: text)
                .font(Typography.cardBody)
                .lineSpacing(Typography.bodyLineSpacing)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(3)
                .wrapsFully()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "Selection: \(text)"))
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
