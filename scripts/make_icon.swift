import AppKit
import Foundation

func drawIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
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
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Background squircle with clip
    let cornerRadius = size * 0.2237
    let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.saveGraphicsState()
    bgPath.setClip()

    let gradient = NSGradient(colors: [
        NSColor(red: 0.58, green: 0.35, blue: 0.96, alpha: 1.0),
        NSColor(red: 0.28, green: 0.22, blue: 0.78, alpha: 1.0),
    ])!
    gradient.draw(in: bgRect, angle: -90)

    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.18),
        NSColor.clear,
    ])!
    highlight.draw(in: NSRect(x: 0, y: size * 0.5, width: size, height: size * 0.5), angle: -90)

    NSGraphicsContext.restoreGraphicsState()

    // Shelf (white pill)
    let shelfW = size * 0.64
    let shelfH = size * 0.085
    let shelfX = (size - shelfW) / 2
    let shelfY = size * 0.32
    let shelfRect = NSRect(x: shelfX, y: shelfY, width: shelfW, height: shelfH)
    let shelfPath = NSBezierPath(roundedRect: shelfRect, xRadius: shelfH / 2, yRadius: shelfH / 2)

    if pixelSize >= 64 {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = size * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
        shadow.set()
        NSColor.white.setFill()
        shelfPath.fill()
        NSGraphicsContext.restoreGraphicsState()
    } else {
        NSColor.white.setFill()
        shelfPath.fill()
    }

    // Items on shelf — three rounded rectangles, varying heights
    let itemCount = 3
    let totalItemW = shelfW * 0.72
    let itemW = totalItemW / CGFloat(itemCount) * 0.78
    let itemSpacing = (totalItemW - itemW * CGFloat(itemCount)) / CGFloat(itemCount - 1)
    let itemsStartX = shelfX + (shelfW - totalItemW) / 2
    let itemY = shelfY + shelfH

    let colors: [NSColor] = [
        NSColor(red: 1.00, green: 0.43, blue: 0.43, alpha: 1.0),
        NSColor(red: 1.00, green: 0.78, blue: 0.26, alpha: 1.0),
        NSColor(red: 0.38, green: 0.82, blue: 0.58, alpha: 1.0),
    ]
    let heights: [CGFloat] = [0.26, 0.32, 0.22]

    if pixelSize >= 64 {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = size * 0.014
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.004)
        shadow.set()

        for i in 0..<itemCount {
            let itemX = itemsStartX + CGFloat(i) * (itemW + itemSpacing)
            let itemH = size * heights[i]
            let rect = NSRect(x: itemX, y: itemY, width: itemW, height: itemH)
            let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.018, yRadius: size * 0.018)
            colors[i].setFill()
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    } else {
        for i in 0..<itemCount {
            let itemX = itemsStartX + CGFloat(i) * (itemW + itemSpacing)
            let itemH = size * heights[i]
            let rect = NSRect(x: itemX, y: itemY, width: itemW, height: itemH)
            let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.018, yRadius: size * 0.018)
            colors[i].setFill()
            path.fill()
        }
    }

    return rep.representation(using: .png, properties: [:])
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputDir = repoRoot
    .appendingPathComponent("DropShelf/Assets.xcassets/AppIcon.appiconset")
    .path

let sizes: [(String, Int)] = [
    ("icon-16.png", 16),
    ("icon-16@2x.png", 32),
    ("icon-32.png", 32),
    ("icon-32@2x.png", 64),
    ("icon-128.png", 128),
    ("icon-128@2x.png", 256),
    ("icon-256.png", 256),
    ("icon-256@2x.png", 512),
    ("icon-512.png", 512),
    ("icon-512@2x.png", 1024),
]

for (filename, pixels) in sizes {
    if let data = drawIcon(pixelSize: pixels) {
        let path = "\(outputDir)/\(filename)"
        try data.write(to: URL(fileURLWithPath: path))
        print("wrote \(filename) (\(pixels)x\(pixels), \(data.count) bytes)")
    }
}
