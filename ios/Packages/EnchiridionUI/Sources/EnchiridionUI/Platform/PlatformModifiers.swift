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

    /// Dragging a scroll view down takes the keyboard down with it (iOS).
    func dismissesKeyboardInteractively() -> some View {
        #if canImport(UIKit)
        scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }
}
