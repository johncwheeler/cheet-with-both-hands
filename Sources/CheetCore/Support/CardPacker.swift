import CoreGraphics

/// Packs variable-size cards into a fixed-width area, top-down, using a skyline "bottom-left" fit:
/// each card goes wherever it can sit highest (leftmost on ties), so cards flow around each other's
/// actual widths and heights. With equal widths this is the classic masonry "shortest column" layout.
public enum CardPacker {
    struct Segment {
        var x: CGFloat
        var width: CGFloat
        var y: CGFloat
        var maxX: CGFloat { x + width }
    }

    private static let epsilon: CGFloat = 0.5

    public static func pack(sizes: [CGSize], containerWidth: CGFloat, spacing: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        guard containerWidth > 0 else { return (sizes.map { CGRect(origin: .zero, size: $0) }, 0) }
        // Each card's footprint includes the gap to its right; the container gets one extra gap to match.
        let total = containerWidth + spacing
        var skyline = [Segment(x: 0, width: total, y: 0)]
        var frames: [CGRect] = []
        frames.reserveCapacity(sizes.count)

        for size in sizes {
            let width = min(max(size.width, 1), containerWidth)
            let footprint = width + spacing
            var candidates = skyline.map(\.x)
            candidates.append(total - footprint)

            var best: (x: CGFloat, y: CGFloat)?
            for x in candidates where x >= -epsilon && x + footprint <= total + epsilon {
                let y = skyline
                    .filter { $0.x < x + footprint - epsilon && $0.maxX > x + epsilon }
                    .map(\.y)
                    .max() ?? 0
                if let current = best {
                    if y < current.y - epsilon || (abs(y - current.y) <= epsilon && x < current.x) {
                        best = (x, y)
                    }
                } else {
                    best = (x, y)
                }
            }
            let origin = best ?? (0, skyline.map(\.y).max() ?? 0)
            let x = max(0, origin.x)
            frames.append(CGRect(x: x, y: origin.y, width: width, height: size.height))
            raise(&skyline, from: x, to: x + footprint, to: origin.y + size.height + spacing)
        }

        let height = frames.map(\.maxY).max() ?? 0
        return (frames, height)
    }

    private static func raise(_ skyline: inout [Segment], from start: CGFloat, to end: CGFloat, to height: CGFloat) {
        var next: [Segment] = []
        for segment in skyline {
            if segment.maxX <= start + epsilon || segment.x >= end - epsilon {
                next.append(segment)
                continue
            }
            if segment.x < start - epsilon {
                next.append(Segment(x: segment.x, width: start - segment.x, y: segment.y))
            }
            if segment.maxX > end + epsilon {
                next.append(Segment(x: end, width: segment.maxX - end, y: segment.y))
            }
        }
        next.append(Segment(x: start, width: end - start, y: height))
        next.sort { $0.x < $1.x }

        var merged: [Segment] = []
        for segment in next {
            if let last = merged.last, abs(last.y - segment.y) <= epsilon, abs(last.maxX - segment.x) <= epsilon {
                merged[merged.count - 1].width += segment.width
            } else {
                merged.append(segment)
            }
        }
        skyline = merged
    }
}
