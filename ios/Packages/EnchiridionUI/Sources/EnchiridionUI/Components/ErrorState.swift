import EnchiridionKit
import SwiftUI

/// Why something couldn't load, and what to do, centered where the content would be: a title, the explanation in
/// muted text, and Retry when there is something to retry. Built from an `EnchiridionError`, a 401 that names this
/// device shows `NotAllowedView` instead, which has no Retry (adding the device on voyager is the fix).
public struct ErrorState: View {
    private enum Content {
        case message(title: String, message: String)
        case notAllowed(Device)
    }

    private let content: Content
    private let retry: (() -> Void)?

    public init(title: String, message: String, retry: (() -> Void)? = nil) {
        content = .message(title: title, message: message)
        self.retry = retry
    }

    /// The error's own words (`EnchiridionError.message`) under a title for its kind.
    public init(_ error: EnchiridionError, retry: (() -> Void)? = nil) {
        if case .unauthorized(let device?) = error {
            content = .notAllowed(device)
        } else {
            content = .message(title: Self.title(for: error), message: Self.message(for: error))
        }
        self.retry = retry
    }

    /// A short headline for an error's kind.
    public static func title(for error: EnchiridionError) -> String {
        switch error {
        case .tailscaleOff, .unreachable, .offline, .restarting, .forbidden: "Can't reach Enchiridion"
        case .unauthorized: "Enchiridion couldn't tell which device this is"
        case .notFound: "Not found"
        case .rejected, .server, .decoding: "Something went wrong"
        }
    }

    /// The explanation under `title(for:)`: the error's message, minus what the title already says.
    public static func message(for error: EnchiridionError) -> String {
        if case .unauthorized(nil) = error { return "Is Tailscale on?" }
        return error.message
    }

    public var body: some View {
        switch content {
        case .notAllowed(let device):
            NotAllowedView(device: device)
        case .message(let title, let message):
            VStack(spacing: Space.state) {
                Text(verbatim: title)
                    .font(Typography.stateTitle)
                    .foregroundStyle(Palette.textHighlighted)
                Text(verbatim: message)
                    .font(Typography.stateMessage)
                    .foregroundStyle(Palette.textMuted)
                    .wrapsFully()
                if let retry {
                    Button(action: retry) {
                        Label("Retry", systemImage: Symbol.retry)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, Space.iconGap)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: Metrics.stateWidth)
        }
    }
}

#if DEBUG
#Preview("Error states") {
    ScrollView {
        VStack(spacing: Space.monthGap) {
            ErrorState(.tailscaleOff) {}
            ErrorState(.unauthorized(device: nil)) {}
            ErrorState(.server(status: 500, message: "Failed query: insert into records … UNIQUE constraint failed"))
            ErrorState(.unauthorized(device: PreviewSamples.device)) {}
        }
        .padding(Space.margin)
        .frame(maxWidth: .infinity)
    }
    .previewRoot()
}
#endif
