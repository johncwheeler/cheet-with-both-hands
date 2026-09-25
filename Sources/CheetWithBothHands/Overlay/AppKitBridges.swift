import AppKit
import CheetCore
import SwiftUI

// MARK: - Appearance helpers

extension RGBAColor {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
    }
}

extension Binding where Value == RGBAColor {
    var color: Binding<Color> {
        Binding<Color>(get: { self.wrappedValue.color }, set: { self.wrappedValue = RGBAColor($0) })
    }
}

extension MaterialStyle {
    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .hud: .hudWindow
        case .popover: .popover
        case .menu: .menu
        case .sidebar: .sidebar
        case .sheet: .sheet
        case .underWindow: .underWindowBackground
        case .fullScreen: .fullScreenUI
        case .tooltip: .toolTip
        case .solid: .windowBackground
        }
    }
}

extension FontDesignChoice {
    var design: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}

extension Appearance {
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family = fontFamily, !family.isEmpty,
           let nsFont = NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size) {
            return Font(nsFont).weight(weight)
        }
        return .system(size: size, weight: weight, design: fontDesign.design)
    }

    var nsAppearance: NSAppearance? {
        switch colorScheme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var swiftUIScheme: ColorScheme? {
        switch colorScheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Visual effect

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var cornerRadius: CGFloat
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.autoresizingMask = [.width, .height]
        update(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        update(view)
    }

    private func update(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blending
        view.maskImage = Self.maskImage(cornerRadius: cornerRadius)
    }

    /// Stretchable rounded-rect mask; the only reliable way to round a behind-window blur.
    static func maskImage(cornerRadius: CGFloat) -> NSImage? {
        guard cornerRadius > 0 else { return nil }
        let edge = 2 * cornerRadius + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}

/// Blurred, tinted, rounded background shared by the overlay, the picker and previews.
struct GlassBackground: View {
    let appearance: Appearance
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    var body: some View {
        let radius = appearance.cornerRadius
        ZStack {
            if appearance.material == .solid {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffectBackground(material: appearance.material.nsMaterial, cornerRadius: radius, blending: blending)
            }
            appearance.tint.color.opacity(appearance.tintStrength)
        }
        .opacity(appearance.backgroundOpacity)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            if appearance.showBorder {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
        }
    }
}

// MARK: - Window dragging & resizing

/// Transparent view that drags its window (used behind the overlay header).
struct WindowDragArea: NSViewRepresentable {
    var onDoubleClick: (() -> Void)? = nil

    final class DragView: NSView {
        var onDoubleClick: (() -> Void)?
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2, let onDoubleClick {
                onDoubleClick()
                return
            }
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.onDoubleClick = onDoubleClick
    }
}

/// Bottom-right grip that resizes a borderless window, keeping its top-left corner fixed.
struct ResizeGrip: NSViewRepresentable {
    final class GripView: NSView {
        private var startFrame = NSRect.zero
        private var startMouse = NSPoint.zero

        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            startFrame = window?.frame ?? .zero
            startMouse = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            (window as? OverlayPanel)?.onUserResize?()
            let mouse = NSEvent.mouseLocation
            let width = max(window.minSize.width, startFrame.width + (mouse.x - startMouse.x))
            let height = max(window.minSize.height, startFrame.height - (mouse.y - startMouse.y))
            window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height), display: true)
        }

        override func resetCursorRects() {
            if #available(macOS 15.0, *) {
                addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
            } else {
                addCursorRect(bounds, cursor: .crosshair)
            }
        }
    }

    func makeNSView(context: Context) -> GripView { GripView() }
    func updateNSView(_ view: GripView, context: Context) {}
}

/// The little diagonal lines drawn under the resize grip.
struct GripGlyph: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<3 {
                let inset = CGFloat(i) * 4 + 3
                var path = Path()
                path.move(to: CGPoint(x: size.width - inset, y: size.height - 2))
                path.addLine(to: CGPoint(x: size.width - 2, y: size.height - inset))
                context.stroke(path, with: .color(.primary.opacity(0.35)), lineWidth: 1)
            }
        }
    }
}

// MARK: - Scroll view access

/// Reports the NSScrollView backing the SwiftUI ScrollView it's placed inside, so it can be
/// scrolled from the keyboard. Invisible and transparent to clicks.
struct EnclosingScrollViewReader: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    final class ProbeView: NSView {
        var onResolve: ((NSScrollView) -> Void)?
        private weak var reported: NSScrollView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolve()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func resolve() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView = self.enclosingScrollView, scrollView !== self.reported else { return }
                self.reported = scrollView
                self.onResolve?(scrollView)
            }
        }
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onResolve = onResolve
        view.resolve()
    }
}
