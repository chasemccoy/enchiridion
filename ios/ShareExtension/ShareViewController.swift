import EnchiridionCore
import EnchiridionKit
import EnchiridionUI
import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The share sheet's "Enchiridion": a card that saves the shared page (or text) as a new artifact record, straight to
/// the server, without the app (ios/ARCHITECTURE.md, "Share flow").
///
/// This class is only glue: it turns the share sheet's item providers into Sendable values, lets
/// `ShareInput.from(javaScript:url:text:)` decide what they mean, and hosts EnchiridionUI's `ShareComposeView` over an
/// EnchiridionCore `ShareComposeModel`, which does the saving (the `.share` client role, a 10 s timeout, and a slug
/// lookup before any retry so a lost answer never makes a second record). There is no outbox: without App Groups the
/// app can't see anything parked here, so a failure stays on the card with Retry and Copy link. An extension gets no
/// launch arguments, so it talks to `Server.production`, unless a DEBUG build's Info.plist names another server
/// (`ENCHIRIDION_SERVER` in `Config/Local.xcconfig`).
final class ShareViewController: UIViewController {
    private var finished = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear                    // the SwiftUI root draws the card's background
        // The extension is its own process with its own bundle (which carries the font files too).
        FontRegistry.register(bundle: .main)
        // As the app does: nothing from the server on the device's disk, should the card ever load an image.
        URLCache.keepMediaInMemory()
        let items = (extensionContext?.inputItems ?? []).compactMap { $0 as? NSExtensionItem }
        Task { [weak self] in
            let input = await Self.readInput(from: items)
            guard let self else { return }
            if let input {
                self.show(input)
            } else {
                self.showNothingToShare()
            }
        }
    }

    /// `Server.production`; a DEBUG build may name a sandbox in its Info.plist. Release builds never read it.
    private static var server: URL {
        #if DEBUG
        Server.fromInfoDictionary(.main) ?? Server.production
        #else
        Server.production
        #endif
    }

    private func show(_ input: ShareInput) {
        let model = ShareComposeModel(input: input, environment: .shareExtension(server: Self.server, bundle: .main))
        host(ShareComposeView(model: model,
                              onDone: { [weak self] in self?.complete() },
                              onCancel: { [weak self] in self?.cancel() }))
        if let url = input.url, input.title == nil {
            Task { if let title = await Self.pageTitle(url) { model.suggestTitle(title) } }
        }
    }

    /// The page's title from its metadata, for a share that came without one (an app that shares only the link).
    /// LinkPresentation loads the page itself; the card is usable meanwhile, and a title typed first is kept.
    private static func pageTitle(_ url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        provider.shouldFetchSubresources = false
        return try? await provider.startFetchingMetadata(for: url).title
    }

    /// Nothing usable came from the share sheet: say so briefly, then close.
    private func showNothingToShare() {
        host(NothingToShareView())
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.cancel()
        }
    }

    private func host(_ root: some View) {
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func complete() {
        guard !finished else { return }
        finished = true
        extensionContext?.completeRequest(returningItems: [])
    }

    private func cancel() {
        guard !finished else { return }
        finished = true
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    // MARK: Reading the shared items

    /// Safari's preprocessing results first, then a URL, then plain text, as Sendable values; `ShareInput` decides
    /// what they mean. nil: nothing to share.
    private static func readInput(from items: [NSExtensionItem]) async -> ShareInput? {
        let providers = items.flatMap { $0.attachments ?? [] }
        func first<T: Sendable>(_ type: UTType, _ load: @MainActor (NSItemProvider) async -> T?) async -> T? {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if let value = await load(provider) { return value }
            }
            return nil
        }
        let javaScript = await first(.propertyList, javaScriptResults)
        let url = await first(.url) { await object(URL.self, from: $0) }
        let text = await first(.plainText) { await object(String.self, from: $0) }
            ?? items.lazy.compactMap { $0.attributedContentText?.string }.first { !$0.isEmpty }
        let itemTitle = items.lazy.compactMap { $0.attributedTitle?.string }.first { !$0.isEmpty }
        return ShareInput.from(javaScript: javaScript, url: url, text: text, itemTitle: itemTitle)
    }

    /// A URL or a string, through the provider's object interface.
    private static func object<T: _ObjectiveCBridgeable & Sendable>(_ type: T.Type,
                                                                    from provider: NSItemProvider) async -> T?
    where T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            _ = provider.loadObject(ofClass: type) { value, _ in continuation.resume(returning: value) }
        }
    }

    /// Preprocess.js's `{url, title, selection, description}`. Safari hands them over as a dictionary item, which
    /// only the legacy `loadItem` returns (deprecated in iOS 27, with no replacement for a dictionary: `loadObject`
    /// needs an NSItemProviderReading class). It is called through `LegacyItemLoading` so the deprecation doesn't
    /// warn, and the values become Sendable strings inside the completion handler, so nothing non-Sendable leaves
    /// the provider's queue.
    private static func javaScriptResults(_ provider: NSItemProvider) async -> [String: String]? {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String: String]?, Never>) in
            (provider as any LegacyItemLoading).loadItem(forTypeIdentifier: UTType.propertyList.identifier,
                                                        options: nil) { item, _ in
                guard let dictionary = item as? NSDictionary,
                      let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary else {
                    continuation.resume(returning: nil)
                    return
                }
                var values: [String: String] = [:]
                for case let (key as String, value as String) in results { values[key] = value }
                continuation.resume(returning: values)
            }
        }
    }
}

/// NSItemProvider's legacy loader, for the one item only it can read: the JavaScript preprocessing results.
private protocol LegacyItemLoading {
    func loadItem(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]?,
                  completionHandler: NSItemProvider.CompletionHandler?)
}

extension NSItemProvider: LegacyItemLoading {}

/// The sheet for a share with nothing usable in it.
private struct NothingToShareView: View {
    var body: some View {
        Text("Nothing to share")
            .font(Typography.stateTitle)
            .foregroundStyle(Palette.textHighlighted)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.detailGap * 2)
            .enchiridionRoot()
    }
}
