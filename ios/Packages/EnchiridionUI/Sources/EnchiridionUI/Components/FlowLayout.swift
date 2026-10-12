import SwiftUI

/// Lays its subviews out left to right, wrapping onto a new line when the next one doesn't fit: the web's
/// `display: flex; flex-wrap: wrap` rows (a card's meta row, the detail's badge row). Each line's items are centered
/// vertically on the line, as the web's `align-items: center` does. A subview wider than the whole row is offered
/// the row's width, so long text wraps inside it instead of overflowing.
public struct FlowLayout: Layout {
    /// Between items on a line.
    public var spacing: CGFloat
    /// Between lines.
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = Space.metaGap, lineSpacing: CGFloat = Space.metaLineGap) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(subviews, width: proposal.width ?? .infinity)
        guard !lines.isEmpty else { return .zero }
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(lines.count - 1)
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for item in line.items {
                let point = CGPoint(x: x, y: y + (line.height - item.size.height) / 2)
                subviews[item.index].place(at: point, anchor: .topLeading, proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            let needed = line.items.isEmpty ? size.width : line.width + spacing + size.width
            if !line.items.isEmpty, needed > maxWidth {
                lines.append(line)
                line = Line()
            }
            line.width = line.items.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.items.append((index, size))
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}
