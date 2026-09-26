import CoreGraphics

/// Arranges windows side by side (up to three) or in a grid, keeping their reading order so tiling
/// tidies an arrangement rather than shuffling it. AppKit coordinates: origin bottom-left, y up.
public enum TileLayout {
    /// A frame for each of `frames` (same order), tiled inside `container`.
    public static func tile(_ frames: [CGRect], in container: CGRect, gap: CGFloat, minWidth: CGFloat) -> [CGRect] {
        let count = frames.count
        guard count > 0 else { return [] }
        var columns = count <= 3 ? count : Int(Double(count).squareRoot().rounded(.up))
        while columns > 1, span(container.width, into: columns, gap: gap) < minWidth { columns -= 1 }
        let rows = (count + columns - 1) / columns
        let rowHeight = span(container.height, into: rows, gap: gap)

        // Reading order: which row band each window's centre falls in (top first), then left to right.
        let band = container.height / CGFloat(rows)
        func row(_ frame: CGRect) -> Int { min(rows - 1, max(0, Int((container.maxY - frame.midY) / band))) }
        let order = frames.indices.sorted { a, b in
            let (rowA, rowB) = (row(frames[a]), row(frames[b]))
            if rowA != rowB { return rowA < rowB }
            if frames[a].midX != frames[b].midX { return frames[a].midX < frames[b].midX }
            return a < b
        }

        var result = frames
        for (position, index) in order.enumerated() {
            let row = position / columns
            let column = position % columns
            let inRow = min(columns, count - row * columns)
            let width = span(container.width, into: inRow, gap: gap)
            let x = container.minX + CGFloat(column) * (width + gap)
            let y = container.maxY - CGFloat(row + 1) * rowHeight - CGFloat(row) * gap
            result[index] = CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(.down), height: rowHeight.rounded(.down))
        }
        return result
    }

    /// Size of each of `parts` pieces of `total` with `gap` between them.
    private static func span(_ total: CGFloat, into parts: Int, gap: CGFloat) -> CGFloat {
        (total - gap * CGFloat(parts - 1)) / CGFloat(parts)
    }
}
