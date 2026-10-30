import SwiftUI

/// The Settings window: General, Modules, one pane per module (from `NotchModule.settingsView()`),
/// and About. Every control writes straight to UserDefaults, and the notch applies it live.
struct SettingsView: View {
    let registry: ModuleRegistry

    /// Reopens on the last pane, like most Mac apps.
    @AppStorage(SettingsView.selectedTabKey) private var selection = "general"
    static let selectedTabKey = "settingsSelectedTab"

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(registry: registry)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")

            ModulesSettingsView(registry: registry)
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
                .tag("modules")

            ForEach(registry.orderedModules, id: \.id) { module in
                if let pane = module.settingsView() {
                    SettingsPane { pane }
                        .tabItem { Label(module.title, systemImage: module.symbol) }
                        .tag(module.id)
                }
            }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag("about")
        }
        .frame(width: SettingsWindowSize.width)
        .background(SettingsWindowSize())
    }
}

/// Keeps the resizable Settings window at the panes' width, and opens it at a height that fits
/// on screen (SwiftUI would otherwise pick its own default size).
private struct SettingsWindowSize: NSViewRepresentable {
    static let width: CGFloat = 500

    func makeNSView(context: Context) -> NSView { WindowHook() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowHook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.contentMaxSize = NSSize(width: SettingsWindowSize.width, height: .greatestFiniteMagnitude)
            // Room for the title bar, tabs and Dock.
            let available = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
            window.setContentSize(NSSize(width: SettingsWindowSize.width, height: min(640, available - 160)))
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
