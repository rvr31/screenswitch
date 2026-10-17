#!/usr/bin/swift
import AppKit

// Regenerate the checked-in icon using only the macOS SDK and iconutil.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let assets = root.appendingPathComponent("assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func monitor(_ rect: NSRect, edge: NSColor, screen: NSColor) {
    rounded(NSRect(x: rect.midX - 24, y: rect.minY - 66, width: 48, height: 80), radius: 12, fill: edge)
    rounded(NSRect(x: rect.midX - 88, y: rect.minY - 80, width: 176, height: 24), radius: 12, fill: edge)
    rounded(rect, radius: 38, fill: edge)
    rounded(rect.insetBy(dx: 22, dy: 22), radius: 18, fill: screen)
}

func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSGradient(starting: color(23, 147, 255), ending: color(35, 64, 196))!.draw(in: tile, angle: -90)

    monitor(NSRect(x: 176, y: 446, width: 428, height: 294),
            edge: color(193, 224, 255), screen: color(40, 107, 199))

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 26
    shadow.set()
    monitor(NSRect(x: 364, y: 308, width: 448, height: 328),
            edge: .white, screen: color(16, 51, 106))
    NSGraphicsContext.restoreGraphicsState()

    rounded(NSRect(x: 456, y: 410, width: 264, height: 110), radius: 55, fill: color(78, 223, 154))
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 618, y: 422, width: 86, height: 86)).fill()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let png = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try render(pixels: points * scale).write(to: png)
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", assets.appendingPathComponent("AppIcon.icns").path, iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
print("Generated assets/AppIcon.icns")
