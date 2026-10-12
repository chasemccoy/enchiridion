import SwiftUI

/// Color: the web app's resolved Nuxt UI tokens (`app/theme.css` over the warm-gray neutral ramp), light and dark.
/// The single source of color in this package: views never use `.primary`, `.secondary`, the `.fill` levels or
/// system backgrounds, so the iOS app reads as the same object as the web one.
public enum Palette {
    /// The page behind the list, the detail and sheets (`--page-bg`).
    public static let page = Swatch(0xFCFCFB, dark: 0x1A1A19)
    /// Cards (`--ui-bg`). In dark mode it equals `page`, so only the border separates a card from the page.
    public static let surface = Swatch(0xFFFFFF, dark: 0x1A1A19)
    /// Hover and pressed fills, code, the parent chip, image placeholders (`--ui-bg-elevated`).
    public static let elevated = Swatch(0xF5F4F2, dark: 0x2C2C2A)
    /// The off track of a switch (`--ui-bg-accented`).
    public static let accented = Swatch(0xE6E4DD, dark: 0x6A6862)
    /// The index toolbar (`--index-chrome`).
    public static let chrome = Swatch(0xF9F9F7, dark: 0x0C0C0B)

    /// Card edges, badge outlines, month-header rules (`--ui-border`).
    public static let border = Swatch(0x0B0B0B, opacity: 0.10, dark: 0xFFFFFF, darkOpacity: 0.10)
    /// Horizontal rules in Markdown, the content panel's edge (`--ui-border-muted`).
    public static let borderMuted = Swatch(0x0B0B0B, opacity: 0.06, dark: 0xFFFFFF, darkOpacity: 0.06)
    /// Checkbox rings, a quote's rule (`--ui-border-accented`).
    public static let borderAccented = Swatch(0x0B0B0B, opacity: 0.18, dark: 0xFFFFFF, darkOpacity: 0.16)

    /// Body text, card titles (`--ui-text`).
    public static let text = Swatch(0x383835, dark: 0xB1AEA4)
    /// The detail title (`--ui-text-highlighted`).
    public static let textHighlighted = Swatch(0x0B0B0B, dark: 0xD5D2C9)
    /// `--ui-text-toned`.
    public static let textToned = Swatch(0x6A6862, dark: 0xD5D2C9)
    /// Bylines, badges, metadata labels and values (`--ui-text-muted`), the same in both modes.
    public static let textMuted = Swatch(0x898781, dark: 0x898781)
    /// Meta rows, month headers, counts, placeholders (`--ui-text-dimmed`).
    public static let textDimmed = Swatch(0xB1AEA4, dark: 0x6A6862)

    /// The tint: links, the selection ring, selected chips, the Curated switch (`--ui-primary`).
    public static let primary = Swatch(0x2A78D6, dark: 0x6DA7EC)
    /// Text and icons on a `primary` fill (`--ui-text-inverted`).
    public static let onPrimary = Swatch(0xFFFFFF, dark: 0x1A1A19)
    public static let success = Swatch(0x009300, dark: 0x0CA30C)
    public static let warning = Swatch(0xFAB219, dark: 0xDB9300)
    /// Errors and destructive actions (`--ui-error`).
    public static let error = Swatch(0xD03B3B, dark: 0xEC7E7E)

    /// A note's bubble: `primary` mixed 12% into `surface` (in oklab, as the web's `ChatBubble` does).
    public static let noteBubble = Swatch(0xE6EFFB, dark: 0x24292E)
    /// The floating nav pill (neutral-800), dark in both modes.
    public static let pill = Swatch(0x2C2C2A, dark: 0x2C2C2A)
    /// `==highlighted==` Markdown: the web's `<mark>` text, and its fill (`#fab219` mixed 35% into white by day,
    /// 15% into the dark page by night, in oklab).
    public static let markText = Swatch(0x734500, dark: 0xFAB219)
    public static let markBackground = Swatch(0xFFE5BF, dark: 0x362E20)
}

/// One of the palette's colors: a light and a dark sRGB value (each with its own opacity), picked by SwiftUI's color
/// scheme and nothing else.
///
/// A `ShapeStyle` rather than a UIKit dynamic color: SwiftUI can't see inside a dynamic color, so any trait change
/// on the window (presenting a sheet sets one on the screen behind it) makes every text using one re-resolve and lay
/// itself out again. A style that reads only `colorScheme` resolves to the same value on such a change. Use it
/// wherever a style goes (`foregroundStyle`, `fill`, `background`, `tint`); `color` is the plain `Color`, for the
/// few APIs that want one (attributed-string runs, a shadow, a separator tint).
public struct Swatch: ShapeStyle, Hashable, Sendable {
    let light: UInt32
    let dark: UInt32
    let lightOpacity: Double
    let darkOpacity: Double

    /// Opaque 0xRRGGBB values.
    init(_ light: UInt32, dark: UInt32) {
        self.init(light, opacity: 1, dark: dark, darkOpacity: 1)
    }

    /// Translucent values, like the web's `rgba()` borders.
    init(_ light: UInt32, opacity: Double, dark: UInt32, darkOpacity: Double) {
        self.light = light
        self.dark = dark
        lightOpacity = opacity
        self.darkOpacity = darkOpacity
    }

    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        resolved(environment.colorScheme)
    }

    /// The value for one color scheme.
    public func resolved(_ scheme: ColorScheme) -> Color.Resolved {
        scheme == .dark ? Self.resolved(dark, opacity: darkOpacity) : Self.resolved(light, opacity: lightOpacity)
    }

    /// The same color as a `Color` that follows the appearance on its own.
    public var color: Color {
        .dynamic(light: Self.components(light, lightOpacity), dark: Self.components(dark, darkOpacity))
    }

    /// The swatch as a view that fills its space (a backdrop, a hairline).
    public var view: some View { Rectangle().fill(self) }

    static func resolved(_ value: UInt32, opacity: Double) -> Color.Resolved {
        let (red, green, blue, alpha) = components(value, opacity)
        return Color.Resolved(colorSpace: .sRGB, red: Float(red), green: Float(green), blue: Float(blue),
                              opacity: Float(alpha))
    }

    /// sRGB components, 0 to 1.
    static func components(_ value: UInt32, _ opacity: Double) -> RGBA {
        (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255, opacity)
    }
}

/// Red, green, blue and opacity, 0 to 1, sRGB.
typealias RGBA = (red: Double, green: Double, blue: Double, opacity: Double)
