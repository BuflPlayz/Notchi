import SwiftUI

/// Startup, how the notch opens, its size and look, the island at rest, and resetting everything.
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
    @AppStorage(Preferences.Key.glassClarity) private var glassClarity = 85.0
    @AppStorage(Preferences.Key.glassStyle) private var glassStyle = GlassStyle.clear
    @AppStorage(Preferences.Key.notchBlend) private var notchBlend = Double(Metrics.Notch.hardwareBlend)
    @AppStorage(Preferences.Key.notchCornerRadius) private var cornerRadius = Double(Metrics.Notch.expandedBottomRadius)
    @AppStorage(Preferences.Key.notchTopCurve) private var topCurve = Double(Metrics.Notch.expandedTopRadius)
    @AppStorage(Preferences.Key.compactAlignment) private var compactAlignment = CompactAlignment.center
    @AppStorage(Preferences.Key.openAnimation) private var openAnimation = OpenAnimation.snappy
    @AppStorage(Preferences.Key.openDuration) private var openDuration = 0.35
    @AppStorage(Preferences.Key.openBounce) private var openBounce = 22.0
    @AppStorage(Preferences.Key.edgeHighlight) private var edgeHighlight = 60.0

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
                Picker("Open animation", selection: $openAnimation) {
                    ForEach(OpenAnimation.allCases) { Text($0.title).tag($0) }
                }
                if openAnimation == .custom {
                    SettingsSliderRow(title: "Duration", value: $openDuration, range: OpenAnimation.durationRange, step: 0.05, unit: "s", fractionDigits: 2)
                    SettingsSliderRow(title: "Bounce", value: $openBounce, range: OpenAnimation.bounceRange, step: 2, unit: "%")
                }
                Toggle("Haptic feedback when opening", isOn: $hapticsEnabled)
                Toggle("Hide in full screen", isOn: $hideInFullScreen)
            } header: {
                Text("Opening")
            } footer: {
                SettingsFootnote("Open animation sets how the notch springs out: Smooth stops without overshooting, Bouncy and Elastic overshoot and settle back. Picking one replays it on the notch. With Reduce Motion on, the notch always fades open. With hover off, click the notch to open it. Moving away or clicking elsewhere closes it either way. In full screen, the notch stays hidden and the top edge is left to the app's menu bar; only the volume and brightness HUD still appears.")
            }

            Section {
                SettingsSliderRow(title: "Live activity width", value: $compactSideWidth, range: Metrics.compactSideWidthRange, step: 2, unit: "pt")
                Picker("Live activity position", selection: $compactAlignment) {
                    ForEach(CompactAlignment.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                SettingsSliderRow(title: "Panel width", value: $expandedWidth, range: Metrics.expandedWidthRange, step: 10, unit: "pt")
                Toggle("Show the island at rest", isOn: $islandVisibleWhenIdle)
            } header: {
                Text("Size")
            } footer: {
                SettingsFootnote("The notch previews the size while you drag. Edges pins live activities to the outer sides with a little padding; the volume and brightness HUD always sits there. The island is what Notchi shows on a main display without a notch; with it hidden, hovering its spot still opens it.")
            }

            Section {
                Picker("Glass", selection: $glassStyle) {
                    ForEach(GlassStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                SettingsSliderRow(title: "Glass clarity", value: $glassClarity, range: 0...100, step: 5, unit: "%")
                SettingsSliderRow(title: "Notch blend", value: $notchBlend, range: Metrics.Notch.hardwareBlendRange, step: 2, unit: "pt")
                SettingsSliderRow(title: "Corner radius", value: $cornerRadius, range: Metrics.Notch.cornerRadiusRange, step: 2, unit: "pt")
                SettingsSliderRow(title: "Top curve", value: $topCurve, range: Metrics.Notch.topCurveRange, step: 2, unit: "pt")
                SettingsSliderRow(title: "Edge highlight", value: $edgeHighlight, range: 0...100, step: 5, unit: "%")
            } header: {
                Text("Appearance")
            } footer: {
                SettingsFootnote("Clear glass keeps what's behind sharp; Frosted blurs it. Clarity sets how much shows through: 0% is solid black, 100% leaves the bottom as bare glass. Notch blend is how far the camera housing's black fades out into the glass. Corner radius rounds the bottom corners and Top curve sets where the notch flares into the top edge; the closed notch scales along. These three apply on displays with a notch. The notch opens to preview while you drag.")
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
