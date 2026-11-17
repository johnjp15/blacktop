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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Blackbar")
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

        menu.addItem(NSMenuItem(title: "Quit Blackbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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
            window.title = "Blackbar Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
