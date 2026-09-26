import CoreGraphics

extension CGRect {
    /// This rect kept inside `container`: at least `minSize` (but no bigger than the container) and
    /// moved, not shrunk, to fit. Rounded to whole points.
    public func clamped(to container: CGRect, minSize: CGSize) -> CGRect {
        var r = self
        r.size.width = min(max(r.width, minSize.width), container.width)
        r.size.height = min(max(r.height, minSize.height), container.height)
        r.origin.x = min(max(r.minX, container.minX), container.maxX - r.width)
        r.origin.y = min(max(r.minY, container.minY), container.maxY - r.height)
        return r.integral
    }
}
