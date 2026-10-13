import SwiftUI

/// A record's note as the web's `ChatBubble` draws it: 12 pt `primary` text on `noteBubble`, 10 pt radius, sized to
/// its text, with a small tail at the bottom left.
public struct NoteBubble: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(verbatim: text)
            .font(Typography.note)
            .foregroundStyle(Palette.primary)
            .wrapsFully()
            .padding(Metrics.notePadding)
            .background(Palette.noteBubble, in: Radius.shape(Radius.noteBubble))
            .background(alignment: .bottomLeading) {
                NoteTail()
                    .fill(Palette.noteBubble)
                    .frame(width: NoteTail.size.width, height: NoteTail.size.height)
                    .offset(x: NoteTail.offset.x, y: NoteTail.offset.y)
            }
            .padding(.leading, NoteTail.leadingMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text("Note: \(text)"))
    }
}

/// The bubble's tail: the web's 13 × 14 SVG path, drawn left of the bubble's bottom-left corner.
struct NoteTail: Shape {
    static let size = CGSize(width: 13, height: 14)
    /// The SVG sits at `left: -5.5px; bottom: 0.246px` of the bubble.
    static let offset = CGPoint(x: -5.5, y: -0.246)
    /// The bubble's `margin-left`, which keeps the tail inside the container.
    static let leadingMargin: CGFloat = 4

    /// `M6 .246c-.175 5.992-1.539 8.89-5.5 13.5 6.117.073 9.128-.306 12.5-3L6 .246Z`, in absolute coordinates and
    /// scaled to `rect` (it is drawn at its own size).
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / Self.size.width
        let sy = rect.height / Self.size.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        path.move(to: point(6, 0.246))
        path.addCurve(to: point(0.5, 13.746), control1: point(5.825, 6.238), control2: point(4.461, 9.136))
        path.addCurve(to: point(13, 10.746), control1: point(6.617, 13.819), control2: point(9.628, 13.44))
        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview("Note bubble") {
    VStack(alignment: .leading, spacing: Space.cardPadding) {
        NoteBubble("Worth rereading before the talk.")
        NoteBubble("A longer note that wraps onto a second line, to check the tail stays tucked under the last line.")
    }
    .padding(Space.margin)
    .previewRoot()
}
#endif
