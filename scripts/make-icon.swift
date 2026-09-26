#!/usr/bin/env swift
// Renders an app icon into an .iconset folder:
//   cheeter  Cheeter on a parchment tile (the default icon)
//   classic  a glassy cheet flanked by ⌘ and ⌥ keycaps — one for each hand
// Usage: swift scripts/make-icon.swift <output.iconset> [cheeter <Cheeter.png> | classic]
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
let output = URL(fileURLWithPath: arguments.first ?? "AppIcon.iconset")
let style = arguments.count > 1 ? arguments[1] : "classic"
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// Cheeter on a parchment tile, cropped by the tile's bottom edge like a portrait.
func drawCheeterIcon(size: CGFloat, character: NSImage) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let s = size / 1024
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        // macOS icon grid: an 824pt body with 100pt margins.
        let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let tile = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor.black.setFill()
        tile.fill()
        ctx.restoreGState()

        ctx.saveGState()
        tile.addClip()
        NSGradient(colors: [
            NSColor(srgbRed: 0.96, green: 0.89, blue: 0.72, alpha: 1),
            NSColor(srgbRed: 0.86, green: 0.73, blue: 0.49, alpha: 1),
        ])!.draw(in: body, angle: -90)
        let height = 900 * s
        let width = height * character.size.width / character.size.height
        character.draw(in: NSRect(x: body.midX - width / 2 + 10 * s, y: body.minY - 70 * s, width: width, height: height))
        ctx.restoreGState()

        NSColor.black.withAlphaComponent(0.25).setStroke()
        tile.lineWidth = 3 * s
        tile.stroke()
        return true
    }
}

func drawClassicIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let s = size / 1024
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

        // Squircle background (macOS icon grid: 824pt body, 100pt margins).
        let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor.black.setFill()
        squircle.fill()
        ctx.restoreGState()

        squircle.addClip()
        NSGradient(colors: [
            NSColor(srgbRed: 0.16, green: 0.17, blue: 0.42, alpha: 1),
            NSColor(srgbRed: 0.36, green: 0.22, blue: 0.62, alpha: 1),
            NSColor(srgbRed: 0.85, green: 0.42, blue: 0.52, alpha: 1),
        ])!.draw(in: body, angle: -60)

        // Soft glow.
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
            .draw(in: NSBezierPath(ovalIn: NSRect(x: 180 * s, y: 520 * s, width: 700 * s, height: 480 * s)), relativeCenterPosition: .zero)

        // The cheet.
        let cheet = NSRect(x: 250 * s, y: 330 * s, width: 524 * s, height: 480 * s)
        let cheetPath = NSBezierPath(roundedRect: cheet, xRadius: 44 * s, yRadius: 44 * s)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 30 * s, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        NSColor.white.withAlphaComponent(0.20).setFill()
        cheetPath.fill()
        ctx.restoreGState()
        NSColor.white.withAlphaComponent(0.45).setStroke()
        cheetPath.lineWidth = 4 * s
        cheetPath.stroke()

        // Rows: key chip + description bar.
        let rows: [(CGFloat, CGFloat)] = [(700, 250), (610, 190), (520, 230), (430, 160)]
        for (y, width) in rows {
            let chip = NSBezierPath(roundedRect: NSRect(x: 300 * s, y: y * s, width: 92 * s, height: 46 * s), xRadius: 12 * s, yRadius: 12 * s)
            NSColor(srgbRed: 0.62, green: 0.84, blue: 1.0, alpha: 0.95).setFill()
            chip.fill()
            let bar = NSBezierPath(roundedRect: NSRect(x: 420 * s, y: (y + 10) * s, width: width * s, height: 26 * s), xRadius: 13 * s, yRadius: 13 * s)
            NSColor.white.withAlphaComponent(0.8).setFill()
            bar.fill()
        }

        // Two keycaps — both hands.
        func keycap(_ symbol: String, at origin: CGPoint) {
            let rect = NSRect(x: origin.x * s, y: origin.y * s, width: 210 * s, height: 200 * s)
            let base = NSBezierPath(roundedRect: rect, xRadius: 40 * s, yRadius: 40 * s)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.45).cgColor)
            NSColor(srgbRed: 0.80, green: 0.81, blue: 0.86, alpha: 1).setFill()
            base.fill()
            ctx.restoreGState()
            let top = NSBezierPath(roundedRect: rect.insetBy(dx: 16 * s, dy: 16 * s).offsetBy(dx: 0, dy: 10 * s), xRadius: 30 * s, yRadius: 30 * s)
            NSGradient(colors: [NSColor.white, NSColor(srgbRed: 0.92, green: 0.93, blue: 0.96, alpha: 1)])!.draw(in: top, angle: -90)
            let font = NSFont.systemFont(ofSize: 110 * s, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(srgbRed: 0.22, green: 0.22, blue: 0.36, alpha: 1)]
            let string = NSAttributedString(string: symbol, attributes: attrs)
            let size = string.size()
            let topRect = rect.insetBy(dx: 16 * s, dy: 16 * s).offsetBy(dx: 0, dy: 10 * s)
            string.draw(at: NSPoint(x: topRect.midX - size.width / 2, y: topRect.midY - size.height / 2 + 4 * s))
        }
        keycap("⌘", at: CGPoint(x: 150, y: 150))
        keycap("⌥", at: CGPoint(x: 664, y: 150))
        return true
    }
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let drawIcon: (CGFloat) -> NSImage
switch style {
case "cheeter":
    guard arguments.count > 2, let character = NSImage(contentsOfFile: arguments[2]) else {
        fatalError("cheeter needs the path to Cheeter.png")
    }
    drawIcon = { drawCheeterIcon(size: $0, character: character) }
case "classic":
    drawIcon = drawClassicIcon
default:
    fatalError("Unknown icon style \(style); use cheeter or classic")
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        writePNG(drawIcon(CGFloat(pixels)), pixels: pixels, to: output.appendingPathComponent(name))
    }
}
print("Wrote \(output.path)")
