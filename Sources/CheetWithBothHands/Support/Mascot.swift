import AppKit
import CheetCore

/// Artwork for the icon schemes: the bundled Cheeter illustrations and app icons, plus the menu bar icon.
@MainActor
enum Mascot {
    /// The full character (splash screen). `nil` when running outside the app bundle.
    static let character: NSImage? = bundledImage("Cheeter")
    /// The head, faded out at the lower edge (cheet picker).
    static let head: NSImage? = bundledImage("CheeterHead")

    private static func bundledImage(_ name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }

    /// Uses the scheme's icon in the Dock, ⌘-Tab, alerts and the About panel. The bundle's own icon
    /// (and so the Finder icon) is Cheeter; the classic icon is swapped in at runtime, since changing
    /// the Finder icon would modify the signed app bundle.
    static func applyAppIcon(for scheme: IconScheme) {
        NSApp.applicationIconImage = scheme == .classic ? classicAppIcon : nil
    }

    private static let classicAppIcon: NSImage? =
        Bundle.main.url(forResource: "ClassicAppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))

    /// Menu bar template icon: Cheeter's ⌘-keycap war hammer, tilted mid-swing.
    static func makeHammerIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Drawn upright around the origin, then tilted and scaled to fit the 18pt canvas.
            context.translateBy(x: 7.0, y: 10.4)
            context.scaleBy(x: 0.8, y: 0.8)
            context.rotate(by: .pi / 5.2)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: -1.35, y: -1, width: 2.7, height: 10.2), xRadius: 1.35, yRadius: 1.35).fill()
            NSBezierPath(roundedRect: NSRect(x: -2.3, y: -0.6, width: 4.6, height: 2.2), xRadius: 0.8, yRadius: 0.8).fill()
            let head = NSRect(x: -7.4, y: -9.2, width: 14.8, height: 8.6)
            NSBezierPath(roundedRect: head, xRadius: 2.4, yRadius: 2.4).fill()
            // Knock the ⌘ out of the keycap.
            context.setBlendMode(.destinationOut)
            let glyph = NSAttributedString(string: "⌘", attributes: [
                .font: NSFont.systemFont(ofSize: 7.8, weight: .heavy), .foregroundColor: NSColor.black,
            ])
            let size = glyph.size()
            glyph.draw(at: NSPoint(x: head.midX - size.width / 2, y: head.midY - size.height / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cheet with Both Hands"
        return image
    }
}
