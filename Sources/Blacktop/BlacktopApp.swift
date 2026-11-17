import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let manager = WallpaperManager()
    private let loginItem = LoginItem()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `Blacktop --snapshot <dir>` writes README screenshots and exits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            writeSnapshots(to: URL(fileURLWithPath: args[i + 1], isDirectory: true))
            exit(0)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Blacktop")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        manager.refresh()
    }

    // Opening the app again (e.g. from Finder or Spotlight) shows settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // Rebuild on open so checkmarks and errors are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(title: "Black Menu Bar", action: #selector(toggleEnabled), keyEquivalent: "b")
        toggle.state = manager.isEnabled ? .on : .off
        menu.addItem(toggle)

        let corners = NSMenuItem(title: "Rounded Corners", action: #selector(toggleRoundCorners), keyEquivalent: "")
        corners.state = manager.roundCorners ? .on : .off
        menu.addItem(corners)

        if let message = manager.lastError {
            let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Refresh Wallpaper", action: #selector(refresh), keyEquivalent: "r"))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Blacktop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
    }

    @objc private func toggleEnabled() {
        manager.isEnabled.toggle()
    }

    @objc private func toggleRoundCorners() {
        manager.roundCorners.toggle()
    }

    @objc private func refresh() {
        manager.refresh()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(manager: manager, loginItem: loginItem)
            ))
            window.title = "Blacktop Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Screenshots

    /// Renders the settings window in light and dark mode, with a neutral
    /// placeholder wallpaper so personal wallpapers don't end up in the README.
    private func writeSnapshots(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("settings-light", NSAppearance.Name.aqua), ("settings-dark", .darkAqua)] {
            let view = SettingsView(manager: manager, loginItem: loginItem, previewWallpaper: Self.placeholderWallpaper())
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()

            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let url = directory.appendingPathComponent("\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("Wrote \(url.path)")
        }

        for (name, enabled) in [("before", false), ("after", true)] {
            let preview = MenuBarPreview(
                wallpaper: Self.placeholderWallpaper(),
                menuBarHeight: manager.mainMenuBarHeight,
                isEnabled: enabled,
                cornerRadius: enabled ? 14 : 0
            )
            .frame(width: 420, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            let renderer = ImageRenderer(content: preview)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            let url = directory.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print("Wrote \(url.path)")
        }
    }

    private static func placeholderWallpaper() -> NSImage {
        NSImage(size: NSSize(width: 840, height: 240), flipped: false) { rect in
            NSGradient(colors: [
                NSColor(red: 0.32, green: 0.22, blue: 0.62, alpha: 1),
                NSColor(red: 0.85, green: 0.38, blue: 0.55, alpha: 1),
                NSColor(red: 0.98, green: 0.66, blue: 0.42, alpha: 1),
            ])?.draw(in: rect, angle: -20)
            return true
        }
    }
}
