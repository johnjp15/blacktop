import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Blackens the menu bar by swapping each screen's wallpaper for a copy with a
/// black strip across the top. The macOS menu bar is translucent over the
/// desktop picture, so a black strip there makes the bar render black (and
/// macOS switches the menu bar text to white automatically).
@MainActor
final class WallpaperManager {
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            refresh()
        }
    }

    var lastError: String?

    private let defaults = UserDefaults.standard
    private let workspace = NSWorkspace.shared
    private let outputDirectory: URL
    /// Maps a generated wallpaper's path to the original wallpaper it was made from.
    private var originals: [String: String]
    private var timer: Timer?

    private enum Keys {
        static let enabled = "enabled"
        static let originals = "originals"
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        outputDirectory = support.appendingPathComponent("Blackbar/Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        originals = defaults.dictionary(forKey: Keys.originals) as? [String: String] ?? [:]

        observeChanges()
    }

    // MARK: - Applying

    /// Brings every screen's current wallpaper in line with `isEnabled`.
    func refresh() {
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
    }

    private func blacken(_ screen: NSScreen) throws {
        guard let current = workspace.desktopImageURL(for: screen) else { return }
        let original = originalURL(for: current)

        let barHeight = menuBarHeight(for: screen)
        let scale = screen.backingScaleFactor
        let pixelSize = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        let barPixels = (barHeight * scale).rounded(.up)

        let output = outputURL(for: original, pixelSize: pixelSize, barPixels: barPixels)
        if current.standardizedFileURL == output.standardizedFileURL { return }

        if !FileManager.default.fileExists(atPath: output.path) {
            let image = try render(original, pixelSize: pixelSize, barPixels: barPixels)
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

    private func outputURL(for original: URL, pixelSize: CGSize, barPixels: CGFloat) -> URL {
        let modified = (try? original.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(original.path)|\(modified)|\(Int(pixelSize.width))x\(Int(pixelSize.height))|\(Int(barPixels))"
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return outputDirectory.appendingPathComponent("\(original.deletingPathExtension().lastPathComponent)-\(digest).png")
    }

    // MARK: - Rendering

    private func render(_ source: URL, pixelSize: CGSize, barPixels: CGFloat) throws -> CGImage {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { throw BlackbarError.unreadableWallpaper(source) }

        guard let context = CGContext(
            data: nil,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw BlackbarError.renderFailed }

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
        context.fill(CGRect(x: 0, y: pixelSize.height - barPixels, width: pixelSize.width, height: barPixels))

        guard let result = context.makeImage() else { throw BlackbarError.renderFailed }
        return result
    }

    private func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw BlackbarError.renderFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BlackbarError.renderFailed }
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

enum BlackbarError: LocalizedError {
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
