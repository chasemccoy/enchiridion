import EnchiridionKit
import SwiftUI

/// This device isn't on Enchiridion's device list (a 401 that names it): the title, the device as "name · id" in
/// mono (selectable), Copy ID, and the one thing to do about it. `compact` is the banner form, leading-aligned;
/// otherwise it sits centered on an empty screen. There is no Retry: coming back to the app tries again.
public struct NotAllowedView: View {
    let device: Device
    let compact: Bool
    @State private var copied = false

    public init(device: Device, compact: Bool = false) {
        self.device = device
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: compact ? .leading : .center, spacing: Space.state) {
            Text("This iPhone isn't on Enchiridion's list yet")
                .font(compact ? Typography.stateMessage.weight(.semibold) : Typography.stateTitle)
                .foregroundStyle(Palette.textHighlighted)
            Text(verbatim: "\(device.name) · \(device.id)")
                .font(Typography.mono)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button(copied ? "Copied" : "Copy ID") {
                Pasteboard.copy(device.id)
                copied = true
            }
            .buttonStyle(.borderless)
            .font(Typography.stateMessage)
            .foregroundStyle(Palette.primary)
            .accessibilityLabel(copied ? "Copied device ID" : "Copy device ID")
            Text("Add it to ~/.enchiridion/devices on voyager.")
                .font(Typography.stateMessage)
                .foregroundStyle(Palette.textMuted)
                .wrapsFully()
        }
        .multilineTextAlignment(compact ? .leading : .center)
        .frame(maxWidth: compact ? .infinity : Metrics.stateWidth, alignment: compact ? .leading : .center)
        .onChange(of: device.id) { copied = false }
    }
}

#if DEBUG
#Preview("Not on the list") {
    VStack(spacing: Space.monthGap) {
        NotAllowedView(device: PreviewSamples.device)
        NotAllowedView(device: PreviewSamples.device, compact: true)
    }
    .padding(Space.margin)
    .previewRoot()
}
#endif
