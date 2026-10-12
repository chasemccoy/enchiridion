// Every UIKit or AppKit touch in EnchiridionUI lives under Platform/, each split by canImport.
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// A color with a light and a dark value, resolved by the system as the appearance changes. Components are
    /// sRGB, 0 to 1.
    static func dynamic(light: RGBA, dark: RGBA) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: value.opacity)
        })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.opacity)
        })
        #endif
    }
}
