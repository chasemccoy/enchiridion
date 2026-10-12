import EnchiridionCore
import EnchiridionKit
import SwiftUI

/// The app's whole hierarchy: the library, its detail column and its sheets. The app target hosts it in its window
/// and does nothing else (it registers the serif and picks the server first).
///
/// The models live here, in `@State`, once: `LibraryModel` (the index, search, selection) and `ConnectionModel`
/// (Settings › Connection), passed down with `.environment(_:)`. The server's origin goes down as `\.serverURL`, which
/// media URLs resolve against.
///
/// Coming back to the app tries again: when it becomes active after the index failed to load (a 401 included, whose
/// not-allowed state has no Retry of its own), or after it sat in the background for a while (`staleAfter`), the
/// index is loaded again. After a shorter time away (a share from Safari, say) it asks for the newest record alone,
/// and reloads only when that one is new (`LibraryModel.refreshIfNewer()`). Detail screens and Settings retry their own
/// failed loads the same way.
public struct EnchiridionRootView: View {
    @State private var library: LibraryModel
    @State private var connection: ConnectionModel
    /// When the scene last went to the background; nil while it is in the foreground.
    @State private var backgroundedAt: Date?
    @Environment(\.scenePhase) private var scenePhase
    private let server: URL
    private let now: @Sendable () -> Date

    /// How long the app can sit in the background before coming back reloads the index: the web app, Readwise syncs
    /// and the share extension add records meanwhile, and nothing pushes them here.
    static let staleAfter: TimeInterval = 15 * 60

    public init(environment: AppEnvironment) {
        _library = State(initialValue: LibraryModel(environment: environment))
        _connection = State(initialValue: ConnectionModel(environment: environment))
        server = environment.server
        now = environment.now
    }

    public var body: some View {
        LibraryScreen()
            .environment(library)
            .environment(connection)
            .environment(\.serverURL, server)
            .enchiridionRoot()
            .onChange(of: scenePhase) { _, phase in
                phaseChanged(phase)
            }
    }

    private func phaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = now()
        case .active:
            let away = backgroundedAt.map { now().timeIntervalSince($0) }
            backgroundedAt = nil
            if library.state.error != nil || (away ?? 0) >= Self.staleAfter {
                Task { await library.refresh() }
            } else if away != nil {
                Task { await library.refreshIfNewer() }
            }
        default:
            break
        }
    }
}

#if DEBUG
#Preview("Library") {
    EnchiridionRootView(environment: .preview())
        .previewRoot()
}

#Preview("Not on the list") {
    EnchiridionRootView(environment: .preview(.notAllowed))
        .previewRoot()
}

#Preview("Tailscale off") {
    EnchiridionRootView(environment: .preview(.tailscaleOff))
        .previewRoot()
}

#Preview("Empty") {
    EnchiridionRootView(environment: .preview(.empty))
        .previewRoot()
}
#endif
