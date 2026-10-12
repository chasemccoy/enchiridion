import EnchiridionCore
import EnchiridionKit
import SwiftUI

/// A record pushed onto the detail column's stack: a linked record, a creator, a parent. `LibraryScreen` registers
/// the destination once, at the stack's root.
struct RecordRoute: Hashable {
    let id: Int
}

/// An open editor sheet, identified by its model, so presenting another editor replaces the sheet.
struct EditorSession: Identifiable {
    let model: RecordEditorModel
    var id: ObjectIdentifier { ObjectIdentifier(model) }
}

/// A record search presented as "Add link": the sheet's item.
struct LinkSession: Identifiable {
    let search: RecordSearchModel
    var id: ObjectIdentifier { ObjectIdentifier(search) }
}

enum RecordURL {
    /// A record's `url` as something `openURL` can open: an http(s) address as stored, or a bare `example.com/page`
    /// with https assumed (the web's links do the same through the browser); nil for anything else (`WebAddress`,
    /// which slugs read the same way).
    static func web(_ text: String?) -> URL? {
        WebAddress.url(text)
    }
}

/// A failed refresh above content that is still worth showing: the error's message with Retry, or, for a 401 that
/// names this device, the compact not-allowed state (which has no Retry: coming back to the app tries again).
struct StatusBanner: View {
    let error: EnchiridionError
    let retry: () -> Void

    var body: some View {
        Group {
            if case .unauthorized(let device?) = error {
                NotAllowedView(device: device, compact: true)
            } else {
                HStack(alignment: .center, spacing: Space.metaGap) {
                    Text(verbatim: error.message)
                        .font(Typography.stateMessage)
                        .foregroundStyle(Palette.text)
                        .wrapsFully()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: retry) {
                        Label("Retry", systemImage: Symbol.retry)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.elevated, in: Radius.shape(Radius.card))
    }
}

/// A quiet state where content would be: nothing loaded yet, nothing matching, nothing selected. A title, an optional
/// explanation, and an optional action.
struct EmptyMessage: View {
    let title: String
    var message: String?
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: Space.state) {
            Text(verbatim: title)
                .font(Typography.stateTitle)
                .foregroundStyle(Palette.text)
            if let message {
                Text(verbatim: message)
                    .font(Typography.stateMessage)
                    .foregroundStyle(Palette.textMuted)
                    .wrapsFully()
            }
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(.bordered)
                    .padding(.top, Space.iconGap)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: Metrics.stateWidth)
        .padding(Space.margin)
    }
}

/// A spinner in `textDimmed`, for a screen with nothing to show yet.
struct LoadingIndicator: View {
    let label: String

    var body: some View {
        ProgressView()
            .tint(Palette.textDimmed)
            .accessibilityLabel(Text(verbatim: label))
    }
}

extension View {
    /// An alert for a curate or delete that failed (a model's `actionError`); dismissing it calls `clear`.
    func actionErrorAlert(_ error: EnchiridionError?, clear: @escaping () -> Void) -> some View {
        alert("Couldn't make that change",
              isPresented: Binding(get: { error != nil }, set: { if !$0 { clear() } }),
              presenting: error) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(verbatim: error.message)
        }
    }
}

enum RecordName {
    /// How a delete confirmation names a record: its title in quotes, or "This record".
    static func deletion(_ title: String?) -> String {
        "\(title.nonBlank.map { "“\($0)”" } ?? "This record") will be deleted from Enchiridion. This can't be undone."
    }
}

/// Dims its label a little while pressed: a card in the list, a byline link. A style of its own also keeps a list
/// from drawing its row highlight behind a card.
struct PressDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A pressable row in a grouped card (a linked record, the Link row): no fill at rest, `elevated` while pressed, edge
/// to edge (the card clips it to its corners), as a list cell highlights.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    Palette.elevated.view
                }
            }
            .contentShape(Rectangle())
    }
}
