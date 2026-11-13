import SwiftUI

/// The Settings window: General, Modules, one pane per module (from `NotchModule.settingsView()`),
/// and About, listed in a sidebar like System Settings. Every control writes straight to
/// UserDefaults, and the notch applies it live.
///
/// A sidebar rather than toolbar tabs: with every module's pane there were more tabs than fit, and
/// the ones AppKit moves into the toolbar's overflow menu can't be opened from there.
struct SettingsView: View {
    let registry: ModuleRegistry

    /// Reopens on the last pane, like most Mac apps.
    @AppStorage(SettingsView.selectedTabKey) private var selection = "general"
    static let selectedTabKey = "settingsSelectedTab"

    var body: some View {
        let panes = SettingsPaneID.all(in: registry)
        // A remembered pane that's gone (its module removed) falls back to General.
        let current = panes.first { $0.id == selection } ?? panes[0]
        NavigationSplitView {
            List(selection: Binding<String?>(
                get: { current.id },
                set: { if let id = $0 { selection = id } }
            )) {
                Section {
                    ForEach(panes.filter { $0.group == .app }) { SettingsSidebarRow(pane: $0) }
                }
                Section {
                    ForEach(panes.filter { $0.group == .module }) { SettingsSidebarRow(pane: $0) }
                }
                Section {
                    ForEach(panes.filter { $0.group == .about }) { SettingsSidebarRow(pane: $0) }
                }
            }
            // The Settings window ignores the column width on its own, so the list holds it open too.
            .frame(minWidth: 200)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(for: current)
                .navigationTitle(current.title)
        }
        .frame(minWidth: SettingsWindowSize.minimumWidth, minHeight: 360)
        .background(SettingsWindowSize())
    }

    @ViewBuilder
    private func detail(for pane: SettingsPaneID) -> some View {
        switch pane.id {
        case "general": GeneralSettingsView(registry: registry)
        case "modules": ModulesSettingsView(registry: registry)
        case "about": AboutSettingsView()
        default:
            if let view = registry.orderedModules.first(where: { $0.id == pane.id })?.settingsView() {
                SettingsPane { view }
                    .environment(\.moduleRegistry, registry)
                    // A fresh form per module, so one pane's scroll position doesn't carry over.
                    .id(pane.id)
            }
        }
    }
}

/// One entry in the Settings sidebar.
private struct SettingsPaneID: Identifiable {
    enum Group { case app, module, about }

    let id: String
    let title: String
    let symbol: String
    let tint: Color
    let group: Group

    @MainActor
    static func all(in registry: ModuleRegistry) -> [SettingsPaneID] {
        // The saved order isn't observable, but every reorder rebuilds `modules`, so reading it
        // keeps the sidebar in the order set in the Modules pane.
        _ = registry.modules
        let modules = registry.orderedModules.compactMap { module -> SettingsPaneID? in
            guard module.settingsView() != nil else { return nil }
            return SettingsPaneID(
                id: module.id, title: module.title, symbol: module.symbol,
                tint: tints[module.id] ?? .gray, group: .module
            )
        }
        return [
            SettingsPaneID(id: "general", title: "General", symbol: "gearshape.fill", tint: .gray, group: .app),
            SettingsPaneID(id: "modules", title: "Modules", symbol: "square.grid.2x2.fill", tint: .blue, group: .app),
        ] + modules + [
            SettingsPaneID(id: "about", title: "About", symbol: "info.circle.fill", tint: .gray, group: .about),
        ]
    }

    /// Icon colors, System Settings style. Modules not listed are grey.
    private static let tints: [String: Color] = [
        "media": .pink,
        "clock": .orange,
        "system": .blue,
        "focus": .indigo,
        "calls": .green,
        "recording": .red,
        "agents": .purple,
        "shelf": .teal,
    ]
}

/// A sidebar row: the pane's symbol in a colored rounded square, then its name.
private struct SettingsSidebarRow: View {
    let pane: SettingsPaneID

    var body: some View {
        Label {
            Text(pane.title)
        } icon: {
            Image(systemName: pane.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .tag(pane.id)
    }
}

/// Opens the Settings window at a size that fits the sidebar and a pane, and on screen (SwiftUI
/// would otherwise pick its own default size). It stays resizable from there.
private struct SettingsWindowSize: NSViewRepresentable {
    static let minimumWidth: CGFloat = 680
    static let width: CGFloat = 740

    func makeNSView(context: Context) -> NSView { WindowHook() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowHook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Room for the title bar and Dock.
            let available = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
            window.setContentSize(NSSize(width: SettingsWindowSize.width, height: min(640, available - 120)))
        }
    }
}

/// A grouped form that fills the Settings window and scrolls when the window is shorter than it.
struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(minHeight: 240, maxHeight: .infinity)
    }
}

/// A labeled slider with its current value shown on the right.
struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<CGFloat>
    let step: Double
    let unit: String
    var fractionDigits = 0

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: Double(range.lowerBound)...Double(range.upperBound), step: step)
                    .labelsHidden()
                    .frame(width: 180)
                Text("\(value, format: .number.precision(.fractionLength(fractionDigits))) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

extension EnvironmentValues {
    /// The registry, for module panes that switch their own module on or off.
    @Entry var moduleRegistry: ModuleRegistry? = nil
}

/// A module's own on/off switch at the top of its pane: the same as its switch in Settings ›
/// Modules. Off stops the module completely.
struct ModuleEnabledToggle: View {
    let moduleID: String
    let title: String
    @Environment(\.moduleRegistry) private var registry

    var body: some View {
        if let registry {
            // `modules` is observed, so the switch follows changes made in the Modules pane too.
            let enabled = registry.modules.contains { $0.id == moduleID }
            let isLastEnabled = enabled && registry.modules.count == 1
            Toggle(title, isOn: Binding(
                get: { enabled },
                set: { registry.setEnabled($0, for: moduleID) }
            ))
            .disabled(isLastEnabled)
            .help(isLastEnabled ? "At least one module stays on." : "")
        }
    }
}

/// Grey explanatory text under a section.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Settings") {
    let registry = ModuleRegistry(defaults: UserDefaults(suiteName: "preview.settings")!)
    registry.register(ClockModule(provider: MockClockProvider()))
    registry.register(MediaModule(provider: MockNowPlayingProvider()))
    return SettingsView(registry: registry)
}
