// Draws Blacktop's app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (run from the repo root)
//
// The design: a display on a white tile, showing an abstract wallpaper with a
// black menu bar across the top — what Blacktop does to your screen.
import AppKit

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Abstract wallpaper: a warm gradient sky with two soft overlapping waves.
func drawWallpaper(in r: NSRect) {
    NSGradient(colors: [rgb(255, 170, 110), rgb(240, 100, 140), rgb(120, 70, 200)])!.draw(in: r, angle: -90)

    func wave(baseline: CGFloat, amplitude: CGFloat, phase: CGFloat, colors: [NSColor]) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX - 10, y: r.minY - 10))
        var x = r.minX - 10
        while x <= r.maxX + 10 {
            let t = (x - r.minX) / r.width
            path.line(to: NSPoint(x: x, y: r.minY + r.height * baseline + amplitude * sin(t * 2 * .pi + phase)))
            x += 4
        }
        path.line(to: NSPoint(x: r.maxX + 10, y: r.minY - 10))
        path.close()
        NSGradient(colors: colors)!.draw(in: path, angle: 0)
    }
    wave(baseline: 0.55, amplitude: r.height * 0.10, phase: 0.6,
         colors: [rgb(255, 120, 150).withAlphaComponent(0.9), rgb(170, 90, 230).withAlphaComponent(0.9)])
    wave(baseline: 0.30, amplitude: r.height * 0.09, phase: 2.6,
         colors: [rgb(90, 60, 190), rgb(60, 110, 230)])
}

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: 1024, height: 1024)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's macOS icon grid: an 824pt rounded square centered on a 1024pt canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = rounded(body, 185)

    // Soft drop shadow, as on standard macOS icons.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 20
    shadow.set()
    NSColor.white.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // White tile.
    NSGradient(colors: [rgb(255, 255, 255), rgb(232, 232, 237)])!.draw(in: shape, angle: -90)

    // Display: wallpaper with a black menu bar across the top.
    let screen = NSRect(x: 220, y: 330, width: 584, height: 400)
    NSGraphicsContext.saveGraphicsState()
    rounded(screen, 40).addClip()
    drawWallpaper(in: screen)
    NSColor.black.setFill()
    NSRect(x: screen.minX, y: screen.maxY - 90, width: screen.width, height: 90).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Stand.
    rgb(160, 160, 170).setFill()
    rounded(NSRect(x: 412, y: 270, width: 200, height: 30), 15).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = drawIcon(pixels: points * scale).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}

try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()

// Also save a preview for the README.
try! fm.createDirectory(atPath: "docs", withIntermediateDirectories: true)
try! drawIcon(pixels: 256).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "docs/icon.png"))

print("Wrote Resources/AppIcon.icns and docs/icon.png")
