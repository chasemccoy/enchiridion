import EnchiridionCore
import EnchiridionKit
import SwiftUI

/// Creates a record or edits one, as a sheet titled "New record" or "Edit record": Title, Type (segmented), URL,
/// Summary, Content (Markdown, multi-line), Notes and Curated, in plain sections on the page color. Cancel and Save
/// sit in the bar; Save waits until the draft has something in it and, for an edit, until something changed (or an
/// update that failed may have landed: `hasUnsettledEdit`). A failed save reads inline at the top and leaves every
/// field as typed, so Save again retries (a create whose answer was lost is looked up by its slug first, so a retry
/// never makes a second record).
///
/// Cancel asks before discarding changes, and the sheet can't be swiped away while it holds any. While saving, both
/// are off, for at most `Timings.editorDeadline`. `onSaved` hears the stored record just before the sheet closes. An
/// edit of a record deleted elsewhere says so here, and the record leaves the library when the sheet closes.
public struct RecordEditorSheet: View {
    let model: RecordEditorModel
    let onSaved: ((Record) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDiscard = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case title, url, summary, content, notes
    }

    public init(model: RecordEditorModel, onSaved: ((Record) -> Void)? = nil) {
        self.model = model
        self.onSaved = onSaved
    }

    public var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.formSection) {
                    if let error = model.state.error {
                        SaveErrorNote(error: error, unconfirmed: model.mayHaveSaved, isNew: model.isNew)
                    }
                    FormSection("Title") {
                        TextField("Title", text: $model.draft.title, prompt: prompt("Untitled record"))
                            .focused($focus, equals: .title)
                            .submitLabel(.next)
                            .onSubmit { focus = .url }
                    }
                    FormSection("Type") {
                        Picker("Type", selection: $model.draft.type) {
                            ForEach(types, id: \.self) { type in
                                Text(verbatim: type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    FormSection("URL") {
                        TextField("URL", text: $model.draft.url, prompt: prompt("example.com"))
                            .urlEntry()
                            .focused($focus, equals: .url)
                            .submitLabel(.next)
                            .onSubmit { focus = .summary }
                    }
                    FormSection("Summary") {
                        TextField("Summary", text: $model.draft.summary,
                                  prompt: prompt("A brief summary of this record"), axis: .vertical)
                            .lineLimit(2 ... 8)
                            .focused($focus, equals: .summary)
                    }
                    FormSection("Content", footer: "Markdown. A single line break stays a line break.") {
                        TextField("Content", text: $model.draft.content,
                                  prompt: prompt("Write something about this record"), axis: .vertical)
                            .lineLimit(6...)
                            .focused($focus, equals: .content)
                    }
                    FormSection("Notes") {
                        TextField("Notes", text: $model.draft.notes, prompt: prompt("Additional notes"),
                                  axis: .vertical)
                            .lineLimit(2 ... 8)
                            .focused($focus, equals: .notes)
                    }
                    FormSection(footer: model.validationMessage) {
                        Toggle("Curated", isOn: $model.draft.isCurated)
                            .tint(Palette.primary)
                    }
                }
                .textFieldStyle(.plain)
                .disabled(model.state.isSaving)
                .frame(maxWidth: Metrics.detailWidth)
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.detailGap)
                .frame(maxWidth: .infinity)
            }
            .dismissesKeyboardInteractively()
            .background(Palette.page)
            .navigationTitle(model.isNew ? "New record" : "Edit record")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { cancel() }
                        .disabled(model.state.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.state.isSaving {
                        LoadingIndicator(label: "Saving")
                    } else {
                        Button("Save") { save() }
                            .disabled(!canSave)
                            .keyboardShortcut("s", modifiers: .command)
                    }
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(holdsChanges || model.state.isSaving)
        .enchiridionRoot()
        .onAppear {
            if model.isNew { focus = .title }
        }
        // A record found deleted elsewhere leaves the rows (and its detail closes) only now, after the error was read.
        .onDisappear { model.close() }
    }

    /// Something to save, and for an edit, something changed.
    private var canSave: Bool {
        model.canSave && (model.isNew || holdsChanges)
    }

    /// Edits closing would lose: the draft's, or an update's that failed and may have landed.
    private var holdsChanges: Bool {
        model.hasChanges || model.hasUnsettledEdit
    }

    /// The type choices, with a type this build doesn't know kept when the record has one.
    private var types: [RecordType] {
        RecordType.known.contains(model.draft.type) ? RecordType.known : RecordType.known + [model.draft.type]
    }

    private func prompt(_ text: String) -> Text {
        Text(verbatim: text).foregroundStyle(Palette.textDimmed)
    }

    private func cancel() {
        if holdsChanges {
            confirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        guard canSave else { return }
        focus = nil
        Task {
            guard let record = await model.save() else { return }
            onSaved?(record)
            dismiss()
        }
    }
}

/// A save that failed, above the form: the not-allowed state for a 401 that names this device, otherwise the error's
/// message in `error`. One whose write may have landed all the same (`RecordEditorModel.mayHaveSaved`) says it couldn't
/// be confirmed, not that it failed.
private struct SaveErrorNote: View {
    let error: EnchiridionError
    let unconfirmed: Bool
    let isNew: Bool

    var body: some View {
        Group {
            if case .unauthorized(let device?) = error {
                NotAllowedView(device: device, compact: true)
            } else {
                VStack(alignment: .leading, spacing: Space.iconGap) {
                    Label(unconfirmed ? "Couldn't confirm the save" : "Couldn't save the record",
                          systemImage: Symbol.failure)
                        .font(Typography.stateMessage.weight(.semibold))
                        .foregroundStyle(Palette.error)
                    Text(verbatim: message)
                        .font(Typography.stateMessage)
                        .foregroundStyle(Palette.text)
                        .wrapsFully()
                }
            }
        }
        .padding(Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.elevated, in: Radius.shape(Radius.card))
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        guard unconfirmed else { return error.message }
        let why = isNew
            ? "The record may be in Enchiridion already. Saving again checks first, so it won't make a second one."
            : "The changes may have reached Enchiridion already. Saving again sends them once more."
        return "\(error.message) \(why)"
    }
}

#if DEBUG
#Preview("New record") {
    RecordEditorSheet(model: RecordEditorModel(environment: .preview()))
        .previewRoot()
}

#Preview("Edit record") {
    RecordEditorSheet(model: RecordEditorModel(draft: RecordDraft(PreviewSamples.record), environment: .preview()))
        .previewRoot()
}
#endif
