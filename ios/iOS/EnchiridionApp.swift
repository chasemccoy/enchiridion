import EnchiridionCore
import EnchiridionKit
import EnchiridionUI
import Foundation
import SwiftUI

/// The app: one window holding the library. The models live in EnchiridionUI's root view, built from the environment
/// made here; this target only registers the serif, keeps media off the disk and picks the server
/// (ios/ARCHITECTURE.md, "Targets").
@main
struct EnchiridionApp: App {
    private let environment: AppEnvironment

    init() {
        // Before the first view draws, so the wordmark and detail titles never flash in the fallback serif. A failure
        // is logged by FontRegistry and leaves Typography on New York.
        FontRegistry.register(bundle: .main)
        // Record images load through the shared URLCache, which would keep small ones on disk.
        URLCache.keepMediaInMemory()
        environment = .live(server: AppServer.url)
    }

    var body: some Scene {
        WindowGroup {
            EnchiridionRootView(environment: environment)
        }
    }
}

/// The server the app and its Shortcuts talk to.
enum AppServer {
    /// `Server.production`; a DEBUG build may point at another API with `-EnchiridionServer <origin>` (the Simulator
    /// on voyager reaches `http://localhost:4321`), else with `ENCHIRIDION_SERVER` in `Config/Local.xcconfig`, which
    /// the share extension reads too. Release builds read neither.
    static var url: URL {
        #if DEBUG
        Server.fromArguments(ProcessInfo.processInfo.arguments,
                             fallback: Server.fromInfoDictionary(.main) ?? Server.production)
        #else
        Server.production
        #endif
    }
}
