#!/usr/bin/env swift
// Prepares the Cheeter mascot images from the source illustration:
//   Cheeter.png      the full character, trimmed (splash screen and app icon)
//   CheeterHead.png  the head, faded out at the edges (cheet picker)
// Usage: swift scripts/make-cheeter-assets.swift Resources/Cheeter/source.webp Resources/Cheeter
import AppKit

let arguments = CommandLine.arguments
let source = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "Resources/Cheeter/source.webp")
let output = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "Resources/Cheeter")

/// The head, in source-image pixels (top-left origin).
let headRect = CGRect(x: 468, y: 84, width: 560, height: 530)

/// RGBA pixels, premultiplied, top row first.
struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = makeContext(&pixels, width, height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }

    /// Background removal left the figure slightly see-through in places; make it opaque, keeping soft edges.
    mutating func solidify(threshold: UInt8 = 160) {
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] >= threshold && pixels[i + 3] < 255 {
            let a = Double(pixels[i + 3])
            for c in 0..<3 { pixels[i + c] = UInt8(min(255, (Double(pixels[i + c]) * 255 / a).rounded())) }
            pixels[i + 3] = 255
        }
    }

    /// Bounding box of visible pixels, grown by `margin`.
    func contentBounds(margin: Int) -> CGRect {
        var minX = width, minY = height, maxX = 0, maxY = 0
        for y in 0..<height {
            for x in 0..<width where alpha(x, y) >= 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return CGRect(x: max(0, minX - margin), y: max(0, minY - margin),
                      width: min(width, maxX + margin + 1) - max(0, minX - margin),
                      height: min(height, maxY + margin + 1) - max(0, minY - margin))
    }

    func cropped(_ rect: CGRect) -> Bitmap {
        let r = rect.integral
        var out = [UInt8](repeating: 0, count: Int(r.width) * Int(r.height) * 4)
        for y in 0..<Int(r.height) {
            let from = ((Int(r.minY) + y) * width + Int(r.minX)) * 4
            let to = y * Int(r.width) * 4
            out.replaceSubrange(to..<(to + Int(r.width) * 4), with: pixels[from..<(from + Int(r.width) * 4)])
        }
        return Bitmap(width: Int(r.width), height: Int(r.height), pixels: out)
    }

    /// Fades the lower corners out along an ellipse (hiding the hammer handle and hand behind the head),
    /// leaving the top half, with the ears, untouched.
    mutating func vignette() {
        let cx = Double(width) * 0.5, cy = Double(height) * 0.45
        let rx = Double(width) * 0.5, ry = Double(height) * 0.62
        for y in Int(cy)..<height {
            for x in 0..<width {
                let dx = (Double(x) - cx) / rx, dy = (Double(y) - cy) / ry
                let d = (dx * dx + dy * dy).squareRoot()
                let t = min(1, max(0, (1.0 - d) / 0.14)) // 1 inside, fading to 0 at the rim
                let factor = t * t * (3 - 2 * t)
                let i = (y * width + x) * 4
                for c in 0..<4 { pixels[i + c] = UInt8((Double(pixels[i + c]) * factor).rounded()) }
            }
        }
    }

    func writePNG(to url: URL) {
        var copy = pixels
        let image = makeContext(&copy, width, height).makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(url.path)") }
        print("Wrote \(url.path) (\(width)×\(height))")
    }
}

func makeContext(_ pixels: inout [UInt8], _ width: Int, _ height: Int) -> CGContext {
    // A bitmap context's buffer stores the image's top row first, matching `Bitmap`'s layout.
    let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context
}

guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fatalError("Couldn't read \(source.path)")
}
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var full = Bitmap(image)
full.solidify()

var head = full.cropped(headRect)
head.vignette()
head.writePNG(to: output.appendingPathComponent("CheeterHead.png"))

full.cropped(full.contentBounds(margin: 8)).writePNG(to: output.appendingPathComponent("Cheeter.png"))
