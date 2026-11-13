import SwiftUI

/// Turn modules on or off and drag to reorder them.
struct ModulesSettingsView: View {
    let registry: ModuleRegistry

    /// The module being dragged, so the rows it passes over can make room for it.
    @State private var draggingID: String?

    // A grouped form like every other pane. A pane without a scroll view at its root blanks the
    // whole Settings window, sidebar included.
    var body: some View {
        SettingsPane {
            Section {
                // Explicit drag and drop rather than `onMove`, which never starts a drag in a
                // macOS form or list. Rows make room as the dragged one passes over them.
                ForEach(registry.orderedModules, id: \.id) { module in
                    row(for: module)
                        .contentShape(Rectangle())
                        .opacity(draggingID == module.id ? 0.4 : 1)
                        .onDrag {
                            draggingID = module.id
                            endDragOnMouseUp()
                            return NSItemProvider(object: module.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: ModuleDropDelegate(
                            targetID: module.id, draggingID: $draggingID, registry: registry
                        ))
                }
            } footer: {
                SettingsFootnote("Drag to reorder. The order sets the tabs in the opened notch, and which module takes the closed notch when two have something to show at once (toasts and HUDs always come first). A module that's off stops completely.")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults", action: registry.resetModules)
                }
            }
        }
    }

    /// A drag dropped outside the rows reports nothing, so watch the button instead.
    private func endDragOnMouseUp() {
        Task { @MainActor in
            while NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            draggingID = nil
        }
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
    }
}

/// Moves the dragged module into a row's place as soon as the drag enters it.
private struct ModuleDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggingID: String?
    let registry: ModuleRegistry

    func validateDrop(info: DropInfo) -> Bool {
        draggingID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        let ids = registry.orderedModules.map(\.id)
        guard let from = ids.firstIndex(of: draggingID), let to = ids.firstIndex(of: targetID) else { return }
        withAnimation(.snappy) {
            registry.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

#Preview("Modules") {
    let registry = ModuleRegistry(defaults: UserDefaults(suiteName: "preview.modules")!)
    registry.register(ClockModule(provider: MockClockProvider()))
    registry.register(MediaModule(provider: MockNowPlayingProvider()))
    return ModulesSettingsView(registry: registry)
        .frame(width: 500)
}
