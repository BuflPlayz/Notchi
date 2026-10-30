import SwiftUI

/// Startup, how the notch opens, its size, the island at rest, and resetting everything.
struct GeneralSettingsView: View {
    let registry: ModuleRegistry

    @AppStorage(Preferences.Key.openOnHover) private var openOnHover = true
    @AppStorage(Preferences.Key.expandDelay) private var expandDelay = 0.15
    @AppStorage(Preferences.Key.collapseDelay) private var collapseDelay = 0.3
    @AppStorage(Preferences.Key.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(Preferences.Key.compactSideWidth) private var compactSideWidth = Double(Metrics.compactSideWidth)
    @AppStorage(Preferences.Key.expandedWidth) private var expandedWidth = Double(Metrics.expandedWidth)
    @AppStorage(Preferences.Key.islandVisibleWhenIdle) private var islandVisibleWhenIdle = true
    @AppStorage(Preferences.Key.hideInFullScreen) private var hideInFullScreen = true

    @State private var launchAtLogin = LaunchAtLogin.shared
    @State private var isConfirmingReset = false

    var body: some View {
        SettingsPane {
            Section("Startup") {
                Toggle("Open Notchi at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.needsApproval {
                    LabeledContent("Turned off in System Settings") {
                        Button("Open Login Items…", action: launchAtLogin.openLoginItemsSettings)
                    }
                }
                if let error = launchAtLogin.lastError {
                    SettingsFootnote(error)
                }
            }

            Section {
                Toggle("Open on hover", isOn: $openOnHover)
                SettingsSliderRow(title: "Open after", value: $expandDelay, range: 0...0.6, step: 0.05, unit: "s", fractionDigits: 2)
                    .disabled(!openOnHover)
                SettingsSliderRow(title: "Close after", value: $collapseDelay, range: 0...1, step: 0.05, unit: "s", fractionDigits: 2)
                Toggle("Haptic feedback when opening", isOn: $hapticsEnabled)
                Toggle("Hide in full screen", isOn: $hideInFullScreen)
            } header: {
                Text("Opening")
            } footer: {
                SettingsFootnote("With hover off, click the notch to open it. Moving away or clicking elsewhere closes it either way. In full screen, the notch stays hidden and the top edge is left to the app's menu bar; only the volume and brightness HUD still appears.")
            }

            Section {
                SettingsSliderRow(title: "Live activity width", value: $compactSideWidth, range: Metrics.compactSideWidthRange, step: 2, unit: "pt")
                SettingsSliderRow(title: "Panel width", value: $expandedWidth, range: Metrics.expandedWidthRange, step: 10, unit: "pt")
                Toggle("Show the island at rest", isOn: $islandVisibleWhenIdle)
            } header: {
                Text("Size")
            } footer: {
                SettingsFootnote("The notch previews the size while you drag. The island is what Notchi shows on a main display without a notch; with it hidden, hovering its spot still opens it.")
            }

            Section {
                Button("Reset All Settings…", role: .destructive) { isConfirmingReset = true }
            }
        }
        .onAppear(perform: launchAtLogin.refresh)
        .confirmationDialog("Reset all Notchi settings?", isPresented: $isConfirmingReset) {
            Button("Reset", role: .destructive, action: resetAll)
        } message: {
            Text("Sizes, behavior, module order and which modules are on go back to their defaults. Permissions and launch at login stay as they are.")
        }
    }

    private func resetAll() {
        Preferences.allKeys.forEach(UserDefaults.standard.removeObject(forKey:))
        registry.resetModules()
    }
}

#Preview("General") {
    GeneralSettingsView(registry: ModuleRegistry(defaults: UserDefaults(suiteName: "preview.general")!))
        .frame(width: 500)
}
