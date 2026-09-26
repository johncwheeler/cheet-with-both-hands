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

    /// This rect if it's still on one of `screens`; otherwise moved (not resized, unless too big) into
    /// `fallback` — for windows whose display has been disconnected.
    public func relocated(ontoScreens screens: [CGRect], fallback: CGRect, minSize: CGSize) -> CGRect {
        screens.contains { $0.intersects(self) } ? self : clamped(to: fallback, minSize: minSize)
    }
}
