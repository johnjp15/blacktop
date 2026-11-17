import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// Mirrors the app's login-item registration so the toggle can bind to it.
@MainActor
@Observable
final class LoginItem {
    var isEnabled = SMAppService.mainApp.status == .enabled
    var error: String?

    func set(_ enabled: Bool) {
        error = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.error = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @Bindable var manager: WallpaperManager
    @Bindable var loginItem: LoginItem
    /// Overrides the wallpaper shown in the preview (used for README screenshots).
    var previewWallpaper: NSImage?

    var body: some View {
        Form {
            Section {
                MenuBarPreview(
                    wallpaper: previewWallpaper ?? manager.previewImage,
                    menuBarHeight: manager.mainMenuBarHeight,
                    isEnabled: manager.isEnabled,
                    cornerRadius: manager.roundCorners ? manager.cornerRadius : 0
                )
                .frame(height: 120)
                .listRowInsets(EdgeInsets())

                Toggle(isOn: $manager.isEnabled) {
                    Text("Black menu bar")
                    Text("Turns the menu bar black on every display")
                }
                .toggleStyle(.switch)
            }

            Section {
                Toggle("Rounded corners", isOn: $manager.roundCorners)
                    .toggleStyle(.switch)
                LabeledContent("Corner radius") {
                    HStack {
                        Slider(value: $manager.cornerRadius, in: WallpaperManager.cornerRadiusRange, step: 1)
                        Text("\(Int(manager.cornerRadius)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(!manager.roundCorners)
            } footer: {
                Text("Rounded corners fill the gaps beside windows' rounded top corners, just below the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!manager.isEnabled)

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.set($0) }
                ))
                .toggleStyle(.switch)
                if let error = loginItem.error {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }

            if let error = manager.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A stylized top-of-screen view: wallpaper, menu bar, and a window beneath it,
/// showing how the current settings will look.
struct MenuBarPreview: View {
    var wallpaper: NSImage?
    var menuBarHeight: CGFloat
    var isEnabled: Bool
    /// Corner radius in screen points; 0 for none.
    var cornerRadius: Double

    private let barHeight: CGFloat = 20
    /// Typical macOS window corner radius, in screen points.
    private let windowRadius: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let scale = barHeight / menuBarHeight
            let full = CGRect(origin: .zero, size: size)

            drawWallpaper(in: &context, rect: full)

            // A window docked to the left edge below the bar, with rounded top corners.
            // Its corner shows the gap that rounded corners fill; the right side
            // leaves wallpaper visible so the other corner stands out.
            let windowRect = CGRect(x: 0, y: barHeight, width: size.width * 0.6, height: size.height - barHeight)
            let r = windowRadius * scale
            let window = UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r, style: .circular)
                .path(in: windowRect)
            context.fill(window, with: .color(Color(nsColor: .windowBackgroundColor)))
            let lights: [Color] = [.red, .yellow, .green]
            for (i, color) in lights.enumerated() {
                let dot = CGRect(x: 12 + CGFloat(i) * 14, y: barHeight + 9, width: 8, height: 8)
                context.fill(Path(ellipseIn: dot), with: .color(color.opacity(0.85)))
            }

            // The menu bar itself.
            let bar = CGRect(x: 0, y: 0, width: size.width, height: barHeight)
            if isEnabled {
                context.fill(Path(bar), with: .color(.black))
                if cornerRadius > 0 {
                    context.fill(fillets(width: size.width, radius: cornerRadius * scale), with: .color(.black))
                }
            } else {
                context.fill(Path(bar), with: .color(.white.opacity(0.35)))
            }
            drawMenuBarItems(in: &context, width: size.width, color: isEnabled ? .white : .black)
        }
        .animation(.default, value: isEnabled)
    }

    private func drawWallpaper(in context: inout GraphicsContext, rect: CGRect) {
        guard let wallpaper, wallpaper.size.width > 0, wallpaper.size.height > 0 else {
            let gradient = Gradient(colors: [.purple, .pink, .orange])
            context.fill(Path(rect), with: .linearGradient(gradient, startPoint: .zero,
                                                           endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            return
        }
        // Aspect-fill, anchored to the top: we're previewing the top of the screen.
        let fill = max(rect.width / wallpaper.size.width, rect.height / wallpaper.size.height)
        let drawSize = CGSize(width: wallpaper.size.width * fill, height: wallpaper.size.height * fill)
        let drawRect = CGRect(x: (rect.width - drawSize.width) / 2, y: 0, width: drawSize.width, height: drawSize.height)
        context.draw(Image(nsImage: wallpaper).resizable(), in: drawRect)
    }

    /// Concave black corners hanging below each end of the bar.
    private func fillets(width: CGFloat, radius r: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: barHeight))
        path.addLine(to: CGPoint(x: r, y: barHeight))
        path.addArc(tangent1End: CGPoint(x: 0, y: barHeight), tangent2End: CGPoint(x: 0, y: barHeight + r), radius: r)
        path.closeSubpath()
        path.move(to: CGPoint(x: width, y: barHeight))
        path.addLine(to: CGPoint(x: width - r, y: barHeight))
        path.addArc(tangent1End: CGPoint(x: width, y: barHeight), tangent2End: CGPoint(x: width, y: barHeight + r), radius: r)
        path.closeSubpath()
        return path
    }

    private func drawMenuBarItems(in context: inout GraphicsContext, width: CGFloat, color: Color) {
        let midY = barHeight / 2
        let limit = CGSize(width: 200, height: barHeight)
        func resolve(_ text: Text, bold: Bool = false) -> GraphicsContext.ResolvedText {
            context.resolve(text.font(.system(size: 10, weight: bold ? .bold : .regular)).foregroundColor(color))
        }

        var x: CGFloat = 12
        let items = [(Text(Image(systemName: "apple.logo")), false), (Text("Finder"), true),
                     (Text("File"), false), (Text("Edit"), false), (Text("View"), false)]
        for (text, bold) in items {
            let resolved = resolve(text, bold: bold)
            context.draw(resolved, at: CGPoint(x: x, y: midY), anchor: .leading)
            x += resolved.measure(in: limit).width + 12
        }

        var right = width - 12
        for text in [Text("9:41 AM"), Text(Image(systemName: "wifi")), Text(Image(systemName: "battery.75percent"))] {
            let resolved = resolve(text)
            context.draw(resolved, at: CGPoint(x: right, y: midY), anchor: .trailing)
            right -= resolved.measure(in: limit).width + 12
        }
    }
}
