import SwiftUI

extension View {
    /// The root of every hierarchy: the app's root view, every sheet and the share card. Sets the tint to `primary`
    /// (links, toggles, the selection ring all follow it) and lays the page color under everything, into the safe
    /// areas. System controls default to capsules in several places (glass and bordered buttons, iOS 27's text-input
    /// border), so their shapes are set here once to the web's 9 pt button radius.
    public func enchiridionRoot() -> some View {
        buttonBorderShape(.roundedRectangle(radius: Radius.button))
            .textInputBorderShape(.roundedRectangle)
            .tint(Palette.primary)
            .background(Palette.page)
    }

    /// Takes the height its text needs at the offered width, whatever height it is offered. Multi-line `Text` in a
    /// stack can be offered a height a fraction short of its lines (rounding with line spacing) and then swaps its
    /// last line for an ellipsis; every wrapping text in this package uses this to rule that out.
    public func wrapsFully() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Buttons

/// The web's raised neutral button ("Delete record", "Upload attachments", Retry): `page` fill, a hairline ring and a
/// soft drop shadow, 12 pt medium text, 28 pt tall (scaled), 9 pt radius. A `.destructive` role sets the text in
/// `error`.
public struct RaisedButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        RaisedButton(configuration: configuration)
    }

    private struct RaisedButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var colorScheme
        @ScaledMetric(relativeTo: .caption) private var height = Metrics.buttonHeight

        var body: some View {
            let shape = Radius.shape(Radius.button)
            configuration.label
                .font(Typography.button)
                .labelStyle(CompactIconLabelStyle(iconSize: Metrics.badgeIcon))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(Metrics.buttonPadding)
                .frame(minHeight: height)
                .background {
                    shape
                        .fill(configuration.isPressed ? Palette.elevated : Palette.page)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.06), radius: 2, y: 1)
                }
                .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.5)
        }

        private var foreground: Swatch {
            configuration.role == .destructive ? Palette.error : Palette.text
        }
    }
}

/// A sheet's or the share card's main action ("Save to Enchiridion"): full width, 44 pt (scaled), `primary` with
/// `onPrimary` text, 9 pt radius. Disabled: `elevated` with `textDimmed` text.
public struct ProminentButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        ProminentButton(configuration: configuration)
    }

    private struct ProminentButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @ScaledMetric(relativeTo: .body) private var height = Metrics.prominentButtonHeight

        var body: some View {
            let shape = Radius.shape(Radius.button)
            configuration.label
                .font(Typography.prominentButton)
                .multilineTextAlignment(.center)
                .foregroundStyle(isEnabled ? Palette.onPrimary : Palette.textDimmed)
                .padding(.horizontal, Space.cardPadding)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(isEnabled ? Palette.primary : Palette.elevated, in: shape)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .contentShape(shape)
        }
    }
}

/// The web's toolbar toggles (xs buttons): soft `primary` when selected (primary text on primary at 10%, 15% while
/// pressed), a neutral ghost otherwise (`text`, `elevated` while pressed). 12 pt medium, 24 pt tall (scaled), 9 pt
/// radius, 14 pt icons.
public struct ChipButtonStyle: ButtonStyle {
    public var isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, isSelected: isSelected)
    }

    private struct Chip: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.isEnabled) private var isEnabled
        @ScaledMetric(relativeTo: .caption) private var height = Metrics.chipHeight

        var body: some View {
            let shape = Radius.shape(Radius.button)
            configuration.label
                .font(Typography.chip)
                .labelStyle(CompactIconLabelStyle(iconSize: Metrics.chipIcon))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Palette.primary : Palette.text)
                .padding(Metrics.chipPadding)
                .frame(minHeight: height)
                .background(fill, in: shape)
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.5)
        }

        private var fill: AnyShapeStyle {
            switch (isSelected, configuration.isPressed) {
            case (true, false): AnyShapeStyle(Palette.primary.opacity(0.10))
            case (true, true): AnyShapeStyle(Palette.primary.opacity(0.15))
            case (false, true): AnyShapeStyle(Palette.elevated)
            case (false, false): AnyShapeStyle(Color.clear)
            }
        }
    }
}

extension ButtonStyle where Self == RaisedButtonStyle {
    /// The web's raised neutral button.
    public static var raised: RaisedButtonStyle { RaisedButtonStyle() }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    /// A sheet's main action, full width in `primary`.
    public static var prominent: ProminentButtonStyle { ProminentButtonStyle() }
}

extension ButtonStyle where Self == ChipButtonStyle {
    /// A toolbar toggle: soft primary when `isSelected`, a neutral ghost otherwise.
    public static func chip(isSelected: Bool) -> ChipButtonStyle { ChipButtonStyle(isSelected: isSelected) }
}

// MARK: Labels

/// An icon and a title 4 pt apart, the icon at a fixed point size (the web forces 12 and 14 px icons whatever the
/// text size) and in the label's color unless the icon sets its own.
public struct CompactIconLabelStyle: LabelStyle {
    let iconSize: CGFloat

    public init(iconSize: CGFloat) {
        self.iconSize = iconSize
    }

    public func makeBody(configuration: Configuration) -> some View {
        CompactIconLabel(configuration: configuration, iconSize: iconSize)
    }
}

private struct CompactIconLabel: View {
    let configuration: LabelStyleConfiguration
    /// Scaled with the caption text the icons sit beside.
    @ScaledMetric private var iconSize: CGFloat

    init(configuration: LabelStyleConfiguration, iconSize: CGFloat) {
        self.configuration = configuration
        _iconSize = ScaledMetric(wrappedValue: iconSize, relativeTo: .caption)
    }

    var body: some View {
        HStack(spacing: Space.iconGap) {
            configuration.icon
                .font(.system(size: iconSize))
            configuration.title
        }
    }
}
