// Draws the DMG window background: an arrow from the app icon to Applications.
// Usage: swift dmg-background.swift <output.png> <scale>
import AppKit

let output = CommandLine.arguments[1]
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let size = NSSize(width: 540, height: 380)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSGradient(colors: [NSColor(white: 0.97, alpha: 1), NSColor(white: 0.90, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), angle: -90)

// Icons sit at x = 140 and 400, y = 180 from the top (Finder coordinates).
let arrowY = size.height - 180
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 220, y: arrowY))
arrow.line(to: NSPoint(x: 310, y: arrowY))
arrow.lineWidth = 6
arrow.lineCapStyle = .round
NSColor(white: 0.55, alpha: 1).setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 322, y: arrowY))
head.line(to: NSPoint(x: 300, y: arrowY + 15))
head.line(to: NSPoint(x: 300, y: arrowY - 15))
head.close()
NSColor(white: 0.55, alpha: 1).setFill()
head.fill()

let text = "Drag Blackbar to Applications to install" as NSString
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(white: 0.35, alpha: 1),
]
let textSize = text.size(withAttributes: attributes)
text.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: 70), withAttributes: attributes)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
