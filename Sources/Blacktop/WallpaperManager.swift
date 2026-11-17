import AppKit
import CryptoKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// Blackens the menu bar by swapping each screen's wallpaper for a copy with a
/// black strip across the top. The macOS menu bar is translucent over the
/// desktop picture, so a black strip there makes the bar render black (and
/// macOS switches the menu bar text to white automatically).
@MainActor
@Observable
final class WallpaperManager {
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            scheduleRefresh()
        }
    }

    /// Adds black rounded fillets below each end of the bar, covering the
    /// wallpaper that peeks out beside windows' rounded top corners.
    var roundCorners: Bool {
        didSet {
            defaults.set(roundCorners, forKey: Keys.roundCorners)
            scheduleRefresh()
        }
    }

    /// Fillet radius in points.
    var cornerRadius: Double {
        didSet {
            defaults.set(cornerRadius, forKey: Keys.cornerRadius)
            scheduleRefresh()
        }
    }

    static let cornerRadiusRange = 4.0...40.0

    var lastError: String?

    /// Downscaled copy of the main screen's original wallpaper, for the settings preview.
    var previewImage: NSImage?

    /// Main screen's menu bar height in points, so the preview can draw to scale.
    var mainMenuBarHeight: CGFloat {
        NSScreen.main.map(menuBarHeight(for:)) ?? NSStatusBar.system.thickness
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let workspace = NSWorkspace.shared
    @ObservationIgnored private let outputDirectory: URL
    /// Maps a generated wallpaper's path to the original wallpaper it was made from.
    @ObservationIgnored private var originals: [String: String]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var previewSource: URL?

    private enum Keys {
        static let enabled = "enabled"
        static let roundCorners = "roundCorners"
        static let cornerRadius = "cornerRadius"
        static let originals = "originals"
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        outputDirectory = support.appendingPathComponent("Blacktop/Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // v0.1.0 shipped as "Blackbar". Carry over its settings and its record of
        // original wallpapers, so turning Blacktop off still restores them.
        if defaults.object(forKey: Keys.originals) == nil,
           let legacy = UserDefaults(suiteName: "com.johnjp15.Blackbar") {
            for key in [Keys.enabled, Keys.roundCorners, Keys.cornerRadius, Keys.originals] {
                if let value = legacy.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
        }

        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        roundCorners = defaults.object(forKey: Keys.roundCorners) as? Bool ?? false
        cornerRadius = defaults.object(forKey: Keys.cornerRadius) as? Double ?? 12
        originals = defaults.dictionary(forKey: Keys.originals) as? [String: String] ?? [:]

        observeChanges()
    }

    // MARK: - Applying

    /// Coalesces rapid setting changes (e.g. dragging a slider) into one refresh.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    /// Brings every screen's current wallpaper in line with the settings.
    func refresh() {
        pendingRefresh?.cancel()
        lastError = nil
        for screen in NSScreen.screens {
            do {
                if isEnabled {
                    try blacken(screen)
                } else {
                    try restore(screen)
                }
            } catch {
                lastError = "\(screen.localizedName): \(error.localizedDescription)"
            }
        }
        updatePreview()
    }

    private func updatePreview() {
        guard let screen = NSScreen.main, let current = workspace.desktopImageURL(for: screen) else { return }
        let original = originalURL(for: current)
        guard original != previewSource else { return }
        previewSource = original

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 800,
        ] as CFDictionary
        if let source = CGImageSourceCreateWithURL(original as CFURL, nil),
           let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
            previewImage = NSImage(cgImage: thumbnail, size: .zero)
        } else {
            previewImage = nil
        }
    }

    private func blacken(_ screen: NSScreen) throws {
        guard let current = workspace.desktopImageURL(for: screen) else { return }
        let original = originalURL(for: current)

        let barHeight = menuBarHeight(for: screen)
        let scale = screen.backingScaleFactor
        let pixelSize = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        let barPixels = (barHeight * scale).rounded(.up)
        let cornerPixels = roundCorners ? (cornerRadius * scale).rounded() : 0

        let output = outputURL(for: original, pixelSize: pixelSize, barPixels: barPixels, cornerPixels: cornerPixels)
        if current.standardizedFileURL == output.standardizedFileURL { return }

        if !FileManager.default.fileExists(atPath: output.path) {
            let image = try render(original, pixelSize: pixelSize, barPixels: barPixels, cornerPixels: cornerPixels)
            try write(image, to: output)
        }

        originals[output.path] = original.path
        defaults.set(originals, forKey: Keys.originals)

        // The generated image matches the screen exactly, so scaling mode is moot.
        var options = workspace.desktopImageOptions(for: screen) ?? [:]
        options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
        options[.allowClipping] = true
        try workspace.setDesktopImageURL(output, for: screen, options: options)
    }

    private func restore(_ screen: NSScreen) throws {
        guard let current = workspace.desktopImageURL(for: screen) else { return }
        let original = originalURL(for: current)
        guard original != current else { return }
        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        try workspace.setDesktopImageURL(original, for: screen, options: options)
    }

    /// If `url` is one of our generated wallpapers, returns the one it was made from.
    private func originalURL(for url: URL) -> URL {
        if let path = originals[url.standardizedFileURL.path] {
            return URL(fileURLWithPath: path)
        }
        return url
    }

    private func menuBarHeight(for screen: NSScreen) -> CGFloat {
        // Notched displays report the notch area as a top safe-area inset.
        let reserved = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
        // When the menu bar auto-hides, visibleFrame doesn't reserve it.
        return reserved > 0 ? reserved : NSStatusBar.system.thickness
    }

    private func outputURL(for original: URL, pixelSize: CGSize, barPixels: CGFloat, cornerPixels: CGFloat) -> URL {
        let modified = (try? original.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(original.path)|\(modified)|\(Int(pixelSize.width))x\(Int(pixelSize.height))|\(Int(barPixels))|\(Int(cornerPixels))"
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return outputDirectory.appendingPathComponent("\(original.deletingPathExtension().lastPathComponent)-\(digest).png")
    }

    // MARK: - Rendering

    private func render(_ source: URL, pixelSize: CGSize, barPixels: CGFloat, cornerPixels: CGFloat) throws -> CGImage {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { throw BlacktopError.unreadableWallpaper(source) }

        guard let context = CGContext(
            data: nil,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw BlacktopError.renderFailed }

        context.interpolationQuality = .high

        // Aspect-fill, centered — matches macOS's default "Fill Screen".
        let imageSize = CGSize(width: image.width, height: image.height)
        let fill = max(pixelSize.width / imageSize.width, pixelSize.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
        let drawRect = CGRect(
            x: (pixelSize.width - drawSize.width) / 2,
            y: (pixelSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.draw(image, in: drawRect)

        // Core Graphics' origin is bottom-left, so the menu bar strip is at the top.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        let barBottom = pixelSize.height - barPixels
        context.fill(CGRect(x: 0, y: barBottom, width: pixelSize.width, height: barPixels))

        // Concave fillets hanging below each end of the bar: the region between
        // the screen corner and a quarter circle curving from bar to screen edge.
        if cornerPixels > 0 {
            let r = cornerPixels
            let w = pixelSize.width
            let fillets = CGMutablePath()
            fillets.move(to: CGPoint(x: 0, y: barBottom))
            fillets.addLine(to: CGPoint(x: r, y: barBottom))
            fillets.addArc(center: CGPoint(x: r, y: barBottom - r), radius: r,
                           startAngle: .pi / 2, endAngle: .pi, clockwise: false)
            fillets.closeSubpath()
            fillets.move(to: CGPoint(x: w, y: barBottom))
            fillets.addLine(to: CGPoint(x: w - r, y: barBottom))
            fillets.addArc(center: CGPoint(x: w - r, y: barBottom - r), radius: r,
                           startAngle: .pi / 2, endAngle: 0, clockwise: true)
            fillets.closeSubpath()
            context.addPath(fillets)
            context.fillPath()
        }

        guard let result = context.makeImage() else { throw BlacktopError.renderFailed }
        return result
    }

    private func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw BlacktopError.renderFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BlacktopError.renderFailed }
    }

    // MARK: - Observing

    private func observeChanges() {
        // Displays connected, disconnected, or rearranged.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        // Each Space can have its own wallpaper, and setDesktopImageURL only affects the current one.
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        // There's no public notification for the user picking a new wallpaper, so poll.
        // refresh() is cheap when nothing changed: it just compares URLs.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
}

enum BlacktopError: LocalizedError {
    case unreadableWallpaper(URL)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .unreadableWallpaper(let url):
            "Can't read wallpaper “\(url.lastPathComponent)”. Dynamic and Aerial wallpapers aren't supported; pick a still image."
        case .renderFailed:
            "Couldn't generate the blackened wallpaper."
        }
    }
}
