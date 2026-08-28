import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render-icon.swift <iconset-directory>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1_024)
]

func renderIcon(pixelSize: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "NetworkSpeedLogger.Icon", code: 1)
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "NetworkSpeedLogger.Icon", code: 2)
    }

    let size = CGFloat(pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let inset = size * 0.055
    let tileRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: size * 0.215, yRadius: size * 0.215)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.08, green: 0.35, blue: 0.98, alpha: 1),
        ending: NSColor(calibratedRed: 0.16, green: 0.72, blue: 0.96, alpha: 1)
    )!
    gradient.draw(in: tile, angle: -55)

    NSColor.white.withAlphaComponent(0.12).setStroke()
    tile.lineWidth = max(1, size * 0.012)
    tile.stroke()

    let graph = NSBezierPath()
    graph.move(to: NSPoint(x: size * 0.20, y: size * 0.40))
    graph.curve(
        to: NSPoint(x: size * 0.43, y: size * 0.48),
        controlPoint1: NSPoint(x: size * 0.29, y: size * 0.40),
        controlPoint2: NSPoint(x: size * 0.34, y: size * 0.50)
    )
    graph.curve(
        to: NSPoint(x: size * 0.61, y: size * 0.69),
        controlPoint1: NSPoint(x: size * 0.50, y: size * 0.46),
        controlPoint2: NSPoint(x: size * 0.52, y: size * 0.67)
    )
    graph.curve(
        to: NSPoint(x: size * 0.80, y: size * 0.62),
        controlPoint1: NSPoint(x: size * 0.69, y: size * 0.72),
        controlPoint2: NSPoint(x: size * 0.72, y: size * 0.62)
    )
    graph.lineCapStyle = .round
    graph.lineJoinStyle = .round
    graph.lineWidth = max(1.5, size * 0.072)
    NSColor.white.setStroke()
    graph.stroke()

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: size * 0.66, y: size * 0.77))
    arrow.line(to: NSPoint(x: size * 0.81, y: size * 0.77))
    arrow.line(to: NSPoint(x: size * 0.81, y: size * 0.62))
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.lineWidth = max(1.2, size * 0.045)
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "NetworkSpeedLogger.Icon", code: 3)
    }
    try png.write(to: url, options: .atomic)
}

for (filename, size) in variants {
    try renderIcon(pixelSize: size, to: outputDirectory.appendingPathComponent(filename))
}
