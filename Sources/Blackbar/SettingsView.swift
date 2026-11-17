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

    var body: some View {
        Form {
            Section {
                Toggle("Black menu bar", isOn: $manager.isEnabled)
                Toggle("Rounded corners", isOn: $manager.roundCorners)
                    .disabled(!manager.isEnabled)
                LabeledContent("Corner radius") {
                    HStack {
                        Slider(value: $manager.cornerRadius, in: WallpaperManager.cornerRadiusRange, step: 1)
                        Text("\(Int(manager.cornerRadius)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(!manager.isEnabled || !manager.roundCorners)
            } footer: {
                Text("Rounded corners fill the gaps beside windows' rounded top corners, just below the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.set($0) }
                ))
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
