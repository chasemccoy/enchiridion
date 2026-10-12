import EnchiridionCore
import EnchiridionKit
import SwiftUI

/// Settings, from the library's gear: Connection (the server's host, how voyager knows this device from `GET /me`
/// in plain words, the device's name and id with Copy ID, the Tailscale account) and About (the version). Nothing is
/// editable: the server is a constant and the device is whatever Tailscale says it is. A device that isn't on the
/// list shows the not-allowed state in place of its rows.
///
/// `/me` is asked on open, on pull, with Check again after a failure, and when the app comes back while Settings is
/// open. Reads `ConnectionModel` and `LibraryModel` (for the version) from the environment.
public struct SettingsSheet: View {
    @Environment(ConnectionModel.self) private var connection
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.formSection) {
                    connectionSection
                    FormSection("About") {
                        HStack(alignment: .firstTextBaseline, spacing: Space.metaGap) {
                            Text("Enchiridion")
                                .font(Typography.wordmark)
                                .foregroundStyle(Palette.text)
                            Spacer(minLength: Space.metaGap)
                            Text(verbatim: "Version \(library.environment.appVersion)")
                                .foregroundStyle(Palette.textMuted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: Metrics.detailWidth)
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.detailGap)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.page)
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .refreshable { await connection.refresh() }
        }
        .enchiridionRoot()
        .task { await connection.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await connection.refresh() } }
        }
    }

    private var connectionSection: some View {
        FormSection("Connection") {
            FormValueRow("Server", connection.host)
            if let status = connection.status {
                HStack(alignment: .center, spacing: Space.metaGap) {
                    Text(verbatim: status)
                        .foregroundStyle(connection.lastError == nil ? Palette.textMuted : Palette.error)
                        .wrapsFully()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if connection.isChecking {
                        LoadingIndicator(label: "Checking")
                            .controlSize(.small)
                    }
                }
            }
            if connection.isNotAllowed, let device = connection.device {
                NotAllowedView(device: device, compact: true)
            } else if let device = connection.device {
                FormValueRow("Device", device.name)
                DeviceIDRow(id: device.id)
            }
            if let user = connection.me?.user.nonBlank {
                FormValueRow("Account", user)
            }
            // Not for a device voyager named and refused: adding it on voyager is the fix, and coming back checks again.
            if connection.lastError != nil, !(connection.isNotAllowed && connection.device != nil) {
                Button {
                    Task { await connection.refresh() }
                } label: {
                    Label("Check again", systemImage: Symbol.retry)
                        .foregroundStyle(Palette.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressDimButtonStyle())
                .disabled(connection.isChecking)
            }
        }
    }
}

/// The device's Tailscale id in mono, selectable, with Copy ID: the line Chase adds to `~/.enchiridion/devices`.
private struct DeviceIDRow: View {
    let id: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.metaGap) {
            Text("Device ID")
                .foregroundStyle(Palette.text)
            Spacer(minLength: Space.metaGap)
            Text(verbatim: id)
                .font(Typography.mono)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button(copied ? "Copied" : "Copy ID") {
                Pasteboard.copy(id)
                copied = true
            }
            .buttonStyle(PressDimButtonStyle())
            .font(Typography.stateMessage)
            .foregroundStyle(Palette.primary)
            .accessibilityLabel(copied ? "Copied device ID" : "Copy device ID")
        }
        .onChange(of: id) { copied = false }
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsSheet()
        .environment(ConnectionModel(environment: .preview()))
        .environment(LibraryModel(environment: .preview()))
        .previewRoot()
}

#Preview("Settings, not on the list") {
    SettingsSheet()
        .environment(ConnectionModel(environment: .preview(.notAllowed)))
        .environment(LibraryModel(environment: .preview(.notAllowed)))
        .previewRoot()
}
#endif
