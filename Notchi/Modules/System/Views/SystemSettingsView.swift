import SwiftUI

/// Settings › System.
struct SystemSettingsView: View {
    let module: SystemModule

    @AppStorage(Preferences.Key.replaceSystemHUD) private var replaceSystemHUD = true
    @AppStorage(Preferences.Key.batteryAlerts) private var batteryAlerts = true

    var body: some View {
        Section {
            Toggle("Replace the volume and brightness HUD", isOn: $replaceSystemHUD)
            LabeledContent("Accessibility") {
                if module.permission.isGranted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Button("Allow…", action: module.requestAccessibility)
                        Button("Open Settings…", action: module.permission.openSettings)
                    }
                }
            }
        } header: {
            Text("Volume and brightness keys")
        } footer: {
            SettingsFootnote("Needs Accessibility, which lets Notchi handle the volume and brightness keys (and see Control Center's Focus indicator, for the Focus module). Notchi reads nothing else. Without it, macOS keeps its own HUD.")
        }

        Section {
            Toggle("Show charging and low battery", isOn: $batteryAlerts)
        } header: {
            Text("Battery")
        } footer: {
            SettingsFootnote("A short toast when you plug in, and when the battery reaches 20%, 10% and 5%.")
        }
    }
}

#Preview("System settings") {
    SettingsPane { SystemSettingsView(module: SystemModule()) }
        .frame(width: 500)
}
