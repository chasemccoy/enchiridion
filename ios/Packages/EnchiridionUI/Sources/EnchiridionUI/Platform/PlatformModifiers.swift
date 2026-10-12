// Every UIKit or AppKit touch in EnchiridionUI lives under Platform/, each split by canImport.
import SwiftUI

extension View {
    /// An inline navigation title on iOS; macOS has only one kind.
    func inlineNavigationTitle() -> some View {
        #if canImport(UIKit)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// The shape a context menu lifts (iOS); macOS menus don't lift anything.
    func contextMenuPreviewShape(_ shape: some Shape) -> some View {
        #if canImport(UIKit)
        contentShape(.contextMenuPreview, shape)
        #else
        self
        #endif
    }

    /// A field for a web address: the URL keyboard, no capitals, no autocorrection (iOS).
    func urlEntry() -> some View {
        #if canImport(UIKit)
        keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }

    /// A menu stays open while its toggles and pickers change (iOS), so several filters can be set at once.
    func keepsMenuOpen() -> some View {
        #if canImport(UIKit)
        menuActionDismissBehavior(.disabled)
        #else
        self
        #endif
    }

    /// A search field that shows without pulling down: in the navigation bar's drawer on iOS.
    func alwaysVisibleSearch(text: Binding<String>, prompt: String) -> some View {
        #if canImport(UIKit)
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(verbatim: prompt))
        #else
        searchable(text: text, prompt: Text(verbatim: prompt))
        #endif
    }

    /// The inset grouped list style (iOS); macOS lists stay inset.
    func groupedList() -> some View {
        #if canImport(UIKit)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    /// Dragging a scroll view down takes the keyboard down with it (iOS).
    func dismissesKeyboardInteractively() -> some View {
        #if canImport(UIKit)
        scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    /// The bottom toolbar, where iOS puts Liquid Glass controls; macOS has none, so the automatic place.
    static var bottomBarOrAutomatic: ToolbarItemPlacement {
        #if canImport(UIKit)
        .bottomBar
        #else
        .automatic
        #endif
    }
}

/// `compact` on a narrow iOS width (an iPhone, a narrow iPad split), `regular` otherwise (and always on macOS, which
/// has no size classes).
struct WidthSwitch<Compact: View, Regular: View>: View {
    @ViewBuilder let compact: () -> Compact
    @ViewBuilder let regular: () -> Regular
    #if canImport(UIKit)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        #if canImport(UIKit)
        if sizeClass == .compact { compact() } else { regular() }
        #else
        regular()
        #endif
    }
}
