import SwiftUI
#if canImport(SafariServices) && canImport(UIKit)
import SafariServices
import UIKit
#endif

extension View {
    /// Opens web links in an in-app browser sheet (`SFSafariViewController`) instead of leaving for Safari. It takes
    /// over the environment's `openURL`, so every link below it goes there: a record's URL, a card's Open link, a
    /// link inside Markdown content. Anything that isn't http(s) (mailto:, tel:, another app's scheme) goes to the
    /// system as before. On macOS, where the package also builds, it does nothing.
    public func inAppBrowser() -> some View {
        modifier(InAppBrowserModifier())
    }
}

/// A URL shown in the browser sheet.
private struct BrowserPage: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct InAppBrowserModifier: ViewModifier {
    @State private var page: BrowserPage?

    func body(content: Content) -> some View {
        #if canImport(SafariServices) && canImport(UIKit)
        content
            .environment(\.openURL, OpenURLAction { url in
                guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                    return .systemAction
                }
                page = BrowserPage(url: url)
                return .handled
            })
            .sheet(item: $page) { page in
                SafariView(url: page.url)
                    .ignoresSafeArea()
            }
        #else
        content
        #endif
    }
}

#if canImport(SafariServices) && canImport(UIKit)
/// `SFSafariViewController` for SwiftUI, with a Close button. Its controls keep the system's glass (iOS 26 deprecates
/// tinting them).
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
