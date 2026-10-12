// Every UIKit or AppKit touch in EnchiridionUI lives under Platform/, each split by canImport.
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The general pasteboard, for Copy actions. Works in the app and in the share extension.
public enum Pasteboard {
    @MainActor
    public static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
