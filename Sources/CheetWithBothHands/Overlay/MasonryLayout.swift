import CheetCore
import SwiftUI

struct CardSizing: Equatable {
    var width: CardWidth = .auto
    var prefersFullWidth = false
}

/// Each card's requested width (auto / column span / fraction).
struct CardSizingKey: LayoutValueKey {
    static let defaultValue = CardSizing()
}

/// Lays cards out on a column grid, letting each card take its own width and height and packing
/// the rest around it (see `CardPacker`).
struct MasonryLayout: Layout {
    var style: RenderStyle
    var maxColumns: Int?

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let metrics = GridMetrics.make(width: width, style: style, maxColumns: maxColumns)
        let sizes = subviews.map { subview -> CGSize in
            let sizing = subview[CardSizingKey.self]
            let cardWidth = metrics.resolve(sizing.width, prefersFullWidth: sizing.prefersFullWidth)
            let height = subview.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height
            return CGSize(width: cardWidth, height: height)
        }
        return CardPacker.pack(sizes: sizes, containerWidth: width, spacing: metrics.spacing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var width = proposal.width ?? 900
        if !width.isFinite { width = 900 }
        return CGSize(width: width, height: arrange(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                // Same open-height proposal as measurement, so tables can't reflow taller than measured.
                proposal: ProposedViewSize(width: frame.width, height: nil)
            )
        }
    }
}

/// Wrapping row (used for keycap sequences so long chords never overflow a column).
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    private func lines(for width: CGFloat, subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (points, CGSize(width: widest, height: y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        lines(for: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = lines(for: bounds.width, subviews: subviews).points
        for (subview, point) in zip(subviews, points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading, proposal: .unspecified)
        }
    }

    /// Align the first line's baseline with neighbouring text in a grid row.
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline, let first = subviews.first else { return nil }
        return bounds.minY + first.dimensions(in: .unspecified)[.firstTextBaseline]
    }
}
