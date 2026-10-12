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
