// Draws the Headroom app icon: an ink squircle with a fuel-gauge arc and
// needle. Run:  swift scripts/make-icon.swift <output-dir>
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func drawIcon(canvas: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // macOS-style squircle: 80% of canvas, centered.
    let inset = canvas * 0.10
    let rect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let radius = rect.width * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Ink background with a barely-there vertical lift.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let colors = [
        CGColor(red: 0.135, green: 0.15, blue: 0.175, alpha: 1),
        CGColor(red: 0.085, green: 0.095, blue: 0.115, alpha: 1)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Gauge geometry: 240° sweep, open at the bottom.
    let center = CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.04)
    let gaugeRadius = rect.width * 0.30
    let lineWidth = rect.width * 0.075
    let startAngle: CGFloat = 210 * .pi / 180   // lower left
    let endAngle: CGFloat = -30 * .pi / 180     // lower right
    // Needle sits at 70% of the sweep: still healthy, but visibly used.
    let needleAngle = startAngle + (endAngle - startAngle) * 0.70

    // Track.
    ctx.setLineCap(.round)
    ctx.setLineWidth(lineWidth)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.addArc(center: center, radius: gaugeRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    ctx.strokePath()

    // Consumed sweep in calm teal.
    ctx.setStrokeColor(CGColor(red: 0.24, green: 0.66, blue: 0.62, alpha: 1))
    ctx.addArc(center: center, radius: gaugeRadius, startAngle: startAngle, endAngle: needleAngle, clockwise: true)
    ctx.strokePath()

    // Needle in signal orange.
    let needleLength = gaugeRadius * 0.78
    let tip = CGPoint(
        x: center.x + cos(needleAngle) * needleLength,
        y: center.y + sin(needleAngle) * needleLength
    )
    ctx.setLineCap(.round)
    ctx.setLineWidth(lineWidth * 0.55)
    ctx.setStrokeColor(CGColor(red: 0.95, green: 0.45, blue: 0.20, alpha: 1))
    ctx.move(to: center)
    ctx.addLine(to: tip)
    ctx.strokePath()

    // Hub.
    ctx.setFillColor(CGColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1))
    let hub = lineWidth * 0.75
    ctx.fillEllipse(in: CGRect(x: center.x - hub / 2, y: center.y - hub / 2, width: hub, height: hub))

    return image
}

func writePNG(_ image: NSImage, to path: String, pixels: Int) {
    guard let tiff = image.tiffRepresentation,
          let source = NSBitmapImageRep(data: tiff) else { return }
    let target = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    target.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    if let png = target.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

let master = drawIcon(canvas: 1024)
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for entry in sizes {
    writePNG(master, to: "\(outputDir)/\(entry.name).png", pixels: entry.pixels)
}
print("iconset written to \(outputDir)")
