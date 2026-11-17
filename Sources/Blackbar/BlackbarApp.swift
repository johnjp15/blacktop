import AppKit
import ServiceManagement

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let manager = WallpaperManager()
    private var statusItem: NSStatusItem!

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

    // Rebuild on open so checkmarks and errors are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(title: "Black Menu Bar", action: #selector(toggleEnabled), keyEquivalent: "b")
        toggle.state = manager.isEnabled ? .on : .off
        menu.addItem(toggle)

        if let message = manager.lastError {
            let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

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

    @objc private func refresh() {
        manager.refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            manager.lastError = "Launch at login: \(error.localizedDescription)"
        }
    }
}
