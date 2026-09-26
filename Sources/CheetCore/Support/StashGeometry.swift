import CoreGraphics

public enum StashEdge: String, CaseIterable, Sendable {
    // Declaration order is the tie-break order: sides before top and bottom.
    case left, right, top, bottom
}

/// Where a cheet window goes when stashed. AppKit coordinates: origin bottom-left, y up.
public enum StashGeometry {
    /// Slides `frame` toward the nearest edge of `visibleFrame` whose screen edge doesn't border
    /// another display alongside the window, leaving `sliver` points inside the visible frame.
    /// If every edge is shared, the nearest edge wins anyway.
    public static func stash(_ frame: CGRect, visibleFrame: CGRect, screenFrame: CGRect, otherScreens: [CGRect],
                             sliver: CGFloat) -> (edge: StashEdge, frame: CGRect) {
        func distance(_ edge: StashEdge) -> CGFloat {
            switch edge {
            case .left: max(0, frame.minX - visibleFrame.minX)
            case .right: max(0, visibleFrame.maxX - frame.maxX)
            case .top: max(0, visibleFrame.maxY - frame.maxY)
            case .bottom: max(0, frame.minY - visibleFrame.minY)
            }
        }
        let open = StashEdge.allCases.filter { !isShared($0, window: frame, screen: screenFrame, others: otherScreens) }
        let candidates = open.isEmpty ? StashEdge.allCases : open
        // min(by:) keeps the first of equal minimums, so declaration order breaks ties.
        let edge = candidates.min { distance($0) < distance($1) } ?? .left

        var stashed = frame
        switch edge {
        case .left: stashed.origin.x = visibleFrame.minX + sliver - frame.width
        case .right: stashed.origin.x = visibleFrame.maxX - sliver
        case .top: stashed.origin.y = visibleFrame.maxY - sliver
        case .bottom: stashed.origin.y = visibleFrame.minY + sliver - frame.height
        }
        return (edge, stashed)
    }

    /// Whether sliding past this edge of the screen would put the window onto another display.
    static func isShared(_ edge: StashEdge, window: CGRect, screen: CGRect, others: [CGRect]) -> Bool {
        func overlaps(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> Bool { a0 < b1 && b0 < a1 }
        func touches(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= 1 }
        return others.contains { other in
            switch edge {
            case .left: touches(other.maxX, screen.minX) && overlaps(other.minY, other.maxY, window.minY, window.maxY)
            case .right: touches(other.minX, screen.maxX) && overlaps(other.minY, other.maxY, window.minY, window.maxY)
            case .top: touches(other.minY, screen.maxY) && overlaps(other.minX, other.maxX, window.minX, window.maxX)
            case .bottom: touches(other.maxY, screen.minY) && overlaps(other.minX, other.maxX, window.minX, window.maxX)
            }
        }
    }
}
