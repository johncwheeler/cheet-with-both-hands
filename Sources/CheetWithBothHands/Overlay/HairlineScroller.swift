import AppKit
import SwiftUI

/// A minimal vertical scroll bar: a thin rounded knob with no track, which thickens a little while
/// hovered or dragged. It stays an overlay scroller (fading when idle, taking no layout space) even
/// when System Settings asks for always-visible scroll bars.
final class HairlineScroller: NSScroller {
    private static let hitWidth: CGFloat = 10
    private static let knobWidth: CGFloat = 3
    private static let activeKnobWidth: CGFloat = 5
    private static let edgeInset: CGFloat = 2.5

    private var isHovering = false {
        didSet { if isHovering != oldValue { needsDisplay = true } }
    }

    override class var isCompatibleWithOverlayScrollers: Bool { self == HairlineScroller.self }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        hitWidth
    }

    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }

    /// Replaces a scroll view's vertical scroller with a hairline (once; safe to call repeatedly).
    static func install(in scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        guard !(scrollView.verticalScroller is HairlineScroller) else { return }
        scrollView.verticalScroller = HairlineScroller()
        scrollView.flashScrollers()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func draw(_ dirtyRect: NSRect) {
        drawKnob()
    }

    override func drawKnob() {
        let slot = rect(for: .knob)
        guard !slot.isEmpty else { return }
        let active = isHovering || hitPart == .knob
        let width = active ? Self.activeKnobWidth : Self.knobWidth
        let knob = NSRect(x: bounds.maxX - Self.edgeInset - width, y: slot.minY + 2,
                          width: width, height: max(0, slot.height - 4))
        NSColor.labelColor.withAlphaComponent(active ? 0.55 : 0.32).setFill()
        NSBezierPath(roundedRect: knob, xRadius: width / 2, yRadius: width / 2).fill()
    }

    /// Only ours: AppKit keeps its own tracking areas on overlay scrollers.
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
    }
}

extension View {
    /// Gives the enclosing `ScrollView` a hairline scroll bar. Apply it to the scroll view's content.
    func hairlineScroller() -> some View {
        background(EnclosingScrollViewReader { HairlineScroller.install(in: $0) })
    }
}
