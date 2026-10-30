import SwiftUI

/// Turn modules on or off and drag to reorder them.
struct ModulesSettingsView: View {
    let registry: ModuleRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(registry.orderedModules, id: \.id) { module in
                    row(for: module)
                }
                .onMove(perform: registry.move)
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .frame(height: CGFloat(registry.allModules.count) * 40 + 12)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            SettingsFootnote("Drag to reorder. The order sets the tabs in the opened notch, and which module takes the closed notch when two have something to show at once (toasts and HUDs always come first). A module that's off stops completely.")

            HStack {
                Spacer()
                Button("Restore Defaults", action: registry.resetModules)
            }
        }
        .padding(20)
    }

    private func row(for module: any NotchModule) -> some View {
        let enabled = registry.isEnabled(module.id)
        let isLastEnabled = enabled && registry.modules.count == 1
        return HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Image(systemName: module.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(enabled ? 0.18 : 0.06)))
                .foregroundStyle(enabled ? Color.accentColor : .secondary)
            Text(module.title)
                .foregroundStyle(enabled ? .primary : .secondary)
            Spacer()
            Toggle(module.title, isOn: Binding(
                get: { registry.isEnabled(module.id) },
                set: { registry.setEnabled($0, for: module.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(isLastEnabled)
            .help(isLastEnabled ? "At least one module stays on." : "")
        }
        .padding(.vertical, 4)
    }
}

#Preview("Modules") {
    let registry = ModuleRegistry(defaults: UserDefaults(suiteName: "preview.modules")!)
    registry.register(ClockModule(provider: MockClockProvider()))
    registry.register(MediaModule(provider: MockNowPlayingProvider()))
    return ModulesSettingsView(registry: registry)
        .frame(width: 500)
}
