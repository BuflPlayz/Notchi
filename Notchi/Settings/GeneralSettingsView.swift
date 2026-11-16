import SwiftUI

/// Startup, how the notch opens, its size and look, the island at rest, and resetting everything.
struct GeneralSettingsView: View {
    let registry: ModuleRegistry

    @AppStorage(Preferences.Key.openOnHover) private var openOnHover = true
    @AppStorage(Preferences.Key.expandDelay) private var expandDelay = Preferences.Default.expandDelay
    @AppStorage(Preferences.Key.collapseDelay) private var collapseDelay = Preferences.Default.collapseDelay
    @AppStorage(Preferences.Key.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(Preferences.Key.compactSideWidth) private var compactSideWidth = Preferences.Default.compactSideWidth
    @AppStorage(Preferences.Key.expandedWidth) private var expandedWidth = Preferences.Default.expandedWidth
    @AppStorage(Preferences.Key.islandVisibleWhenIdle) private var islandVisibleWhenIdle = Preferences.Default.islandVisibleWhenIdle
    @AppStorage(Preferences.Key.hideInFullScreen) private var hideInFullScreen = true
    @AppStorage(Preferences.Key.menuBarSafeZone) private var menuBarSafeZone = true
    @AppStorage(Preferences.Key.notchDisplay) private var notchDisplay = NotchDisplay.main
    @AppStorage(Preferences.Key.glassClarity) private var glassClarity = Preferences.Default.glassClarity
    @AppStorage(Preferences.Key.glassStyle) private var glassStyle = GlassStyle.clear
    @AppStorage(Preferences.Key.notchBlend) private var notchBlend = Preferences.Default.notchBlend
    @AppStorage(Preferences.Key.notchCornerRadius) private var cornerRadius = Preferences.Default.notchCornerRadius
    @AppStorage(Preferences.Key.notchTopCurve) private var topCurve = Preferences.Default.notchTopCurve
    @AppStorage(Preferences.Key.compactAlignment) private var compactAlignment = CompactAlignment.center
    @AppStorage(Preferences.Key.compactLip) private var compactLip = Preferences.Default.compactLip
    @AppStorage(Preferences.Key.openAnimation) private var openAnimation = OpenAnimation.snappy
    @AppStorage(Preferences.Key.openDuration) private var openDuration = Preferences.Default.openDuration
    @AppStorage(Preferences.Key.openBounce) private var openBounce = Preferences.Default.openBounce
    @AppStorage(Preferences.Key.edgeHighlight) private var edgeHighlight = Preferences.Default.edgeHighlight

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
                Picker("Show on", selection: $notchDisplay) {
                    ForEach(NotchDisplay.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Display")
            } footer: {
                SettingsFootnote("Main display is the one with the menu bar in System Settings › Displays. Built-in display keeps Notchi in the MacBook's notch even when an external display is main; with the lid closed it moves to the main display until the built-in screen is back.")
            }

            if Self.hasMenuBarLiveActivities {
                Section {
                    LabeledContent("macOS Live Activities") {
                        Button("Open Menu Bar Settings…", action: Self.openMenuBarSettings)
                    }
                } footer: {
                    SettingsFootnote("macOS can show Live Activities in the menu bar too, so a timer or what's playing can appear twice: in the notch and beside it. In System Settings › Menu Bar, scroll down to Live Activities and turn off the apps Notchi already shows. Other apps can't hide these for you.")
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
                Toggle("Make room for menu bar icons", isOn: $menuBarSafeZone)
            } header: {
                Text("Opening")
            } footer: {
                SettingsFootnote("Open animation sets how the notch springs out: Smooth stops without overshooting, Bouncy and Elastic overshoot and settle back. Picking one replays it on the notch. With Reduce Motion on, the notch always fades open. With hover off, click the notch to open it. Moving away or clicking elsewhere closes it either way. In full screen, the notch stays hidden and the top edge is left to the app's menu bar; only the volume and brightness HUD still appears. With Make room for menu bar icons on, a live activity tucks back into the notch while the pointer is on the menu bar beside it, so the icons it covers show and take clicks; open the notch from its middle instead.")
            }

            Section {
                SettingsSliderRow(title: "Live activity width", value: $compactSideWidth, range: Metrics.compactSideWidthRange, step: 2, unit: "pt")
                // Shown as the closed notch's height: the physical notch's, plus the lip below it.
                SettingsSliderRow(
                    title: "Live activity height",
                    value: Binding(get: { notchHeight + compactLip }, set: { compactLip = $0 - notchHeight }),
                    range: CGFloat(notchHeight) + Metrics.Notch.compactBottomLipRange.lowerBound...CGFloat(notchHeight) + Metrics.Notch.compactBottomLipRange.upperBound,
                    step: 0.5,
                    unit: "pt",
                    fractionDigits: 1
                )
                Picker("Live activity position", selection: $compactAlignment) {
                    ForEach(CompactAlignment.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                SettingsSliderRow(title: "Panel width", value: $expandedWidth, range: Metrics.expandedWidthRange, step: 10, unit: "pt")
                Toggle("Show the island at rest", isOn: $islandVisibleWhenIdle)
            } header: {
                Text("Size")
            } footer: {
                SettingsFootnote("The notch previews the size while you drag. Live activity height goes from flush with the camera housing to a few points below it, on displays with a notch; the shorter it is, the more its outline fades out before the housing. Edges pins live activities to the outer sides with a little padding; the volume and brightness HUD always sits there. The island is what Notchi shows on a main display without a notch; with it hidden, hovering its spot still opens it.")
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

    /// macOS 26 and later can put Live Activities in the menu bar, next to (or under) the notch's own.
    private static var hasMenuBarLiveActivities: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }

    /// Opens System Settings › Menu Bar, where the Live Activities switch is.
    private static func openMenuBarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The notch display's physical notch height, or a typical one when it has no notch.
    private var notchHeight: Double {
        let top = ScreenTracker.notchDisplay?.safeAreaInsets.top ?? 0
        return top > 0 ? Double(top) : 32
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
