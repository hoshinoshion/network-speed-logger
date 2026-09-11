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

func roundedPolygon(points: [NSPoint], radius: CGFloat) -> NSBezierPath {
    precondition(points.count >= 3)

    let path = NSBezierPath()
    path.move(to: points[points.count - 1])
    for index in points.indices {
        path.appendArc(
            from: points[index],
            to: points[(index + 1) % points.count],
            radius: radius
        )
    }
    path.close()
    return path
}

func drawArrow(center: NSPoint, width: CGFloat, height: CGFloat, pointsUp: Bool, canvasSize: CGFloat) {
    let halfWidth = width / 2
    let halfHeight = height / 2
    let shaftHalfWidth = width * 0.17
    let top = center.y + halfHeight
    let bottom = center.y - halfHeight
    let headBase = pointsUp ? top - height * 0.47 : bottom + height * 0.47

    let points: [NSPoint]
    if pointsUp {
        points = [
            NSPoint(x: center.x - shaftHalfWidth, y: bottom),
            NSPoint(x: center.x + shaftHalfWidth, y: bottom),
            NSPoint(x: center.x + shaftHalfWidth, y: headBase),
            NSPoint(x: center.x + halfWidth, y: headBase),
            NSPoint(x: center.x, y: top),
            NSPoint(x: center.x - halfWidth, y: headBase),
            NSPoint(x: center.x - shaftHalfWidth, y: headBase)
        ]
    } else {
        points = [
            NSPoint(x: center.x - shaftHalfWidth, y: top),
            NSPoint(x: center.x + shaftHalfWidth, y: top),
            NSPoint(x: center.x + shaftHalfWidth, y: headBase),
            NSPoint(x: center.x + halfWidth, y: headBase),
            NSPoint(x: center.x, y: bottom),
            NSPoint(x: center.x - halfWidth, y: headBase),
            NSPoint(x: center.x - shaftHalfWidth, y: headBase)
        ]
    }
    let arrow = roundedPolygon(points: points, radius: canvasSize * 0.022)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = max(0.5, canvasSize * 0.024)
    shadow.shadowOffset = NSSize(width: 0, height: -canvasSize * 0.014)
    shadow.set()

    let arrowGradient = NSGradient(
        starting: NSColor.white,
        ending: NSColor(calibratedRed: 0.90, green: 0.95, blue: 1.0, alpha: 1)
    )!
    arrowGradient.draw(in: arrow, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.50).setStroke()
    arrow.lineWidth = max(0.7, canvasSize * 0.010)
    arrow.stroke()
}

func validateCoverage(_ bitmap: NSBitmapImageRep, pixelSize: Int) throws {
    var visiblePixels = 0
    var minimumX = pixelSize
    var minimumY = pixelSize
    var maximumX = -1
    var maximumY = -1

    for y in 0..<pixelSize {
        for x in 0..<pixelSize {
            guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.05 else { continue }
            visiblePixels += 1
            minimumX = min(minimumX, x)
            minimumY = min(minimumY, y)
            maximumX = max(maximumX, x)
            maximumY = max(maximumY, y)
        }
    }

    let minimumVisiblePixels = Int(Double(pixelSize * pixelSize) * 0.55)
    let maximumInset = Int(Double(pixelSize) * 0.12)
    guard visiblePixels >= minimumVisiblePixels,
          minimumX <= maximumInset,
          minimumY <= maximumInset,
          maximumX >= pixelSize - maximumInset - 1,
          maximumY >= pixelSize - maximumInset - 1 else {
        throw NSError(
            domain: "NetworkSpeedLogger.Icon",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Rendered icon coverage is incomplete at \(pixelSize)x\(pixelSize)."]
        )
    }
}

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
    context.shouldAntialias = true

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let inset = size * 0.065
    let tileRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: size * 0.215, yRadius: size * 0.215)

    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    tileShadow.shadowBlurRadius = max(0.8, size * 0.040)
    tileShadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)
    tileShadow.set()
    NSColor(calibratedRed: 0.05, green: 0.27, blue: 0.95, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    let tileGradient = NSGradient(
        starting: NSColor(calibratedRed: 0.04, green: 0.25, blue: 0.98, alpha: 1),
        ending: NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.98, alpha: 1)
    )!
    tileGradient.draw(in: tile, angle: -48)

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()

    let lowerGlass = NSBezierPath()
    lowerGlass.move(to: NSPoint(x: size * 0.13, y: size * 0.05))
    lowerGlass.curve(
        to: NSPoint(x: size * 0.96, y: size * 0.68),
        controlPoint1: NSPoint(x: size * 0.25, y: size * 0.20),
        controlPoint2: NSPoint(x: size * 0.74, y: size * 0.70)
    )
    lowerGlass.line(to: NSPoint(x: size, y: 0))
    lowerGlass.line(to: NSPoint(x: 0, y: 0))
    lowerGlass.close()
    NSColor.white.withAlphaComponent(0.10).setFill()
    lowerGlass.fill()
    NSColor.white.withAlphaComponent(0.42).setStroke()
    lowerGlass.lineWidth = max(0.7, size * 0.008)
    lowerGlass.stroke()

    let topHighlight = NSGradient(
        starting: NSColor.white.withAlphaComponent(0.24),
        ending: NSColor.white.withAlphaComponent(0)
    )!
    topHighlight.draw(
        in: NSRect(x: tileRect.minX, y: size * 0.56, width: tileRect.width, height: size * 0.40),
        angle: -90
    )

    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.38).setStroke()
    tile.lineWidth = max(0.8, size * 0.012)
    tile.stroke()

    drawArrow(
        center: NSPoint(x: size * 0.35, y: size * 0.65),
        width: size * 0.265,
        height: size * 0.285,
        pointsUp: true,
        canvasSize: size
    )
    drawArrow(
        center: NSPoint(x: size * 0.66, y: size * 0.35),
        width: size * 0.265,
        height: size * 0.285,
        pointsUp: false,
        canvasSize: size
    )

    NSGraphicsContext.restoreGraphicsState()

    try validateCoverage(bitmap, pixelSize: pixelSize)

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "NetworkSpeedLogger.Icon", code: 3)
    }
    try png.write(to: url, options: .atomic)
}

for (filename, size) in variants {
    try renderIcon(pixelSize: size, to: outputDirectory.appendingPathComponent(filename))
}
