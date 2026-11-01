import SwiftUI

/// The full panel: a header band (module switcher left of the notch, menu right of it)
/// and the selected module's page below.
struct ExpandedContentView: View {
    let model: NotchViewModel
    let layout: NotchLayout

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: layout.headerHeight)

            if model.isDragging, let dropHandler = model.dropHandler {
                dropHandler.dropView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.notchDropFinished, model.dropFinished)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let module = model.selectedModule {
                module.expandedView()
                    .id(module.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, layout.horizontalInset + 12)
        .padding(.bottom, 14)
        .foregroundStyle(Theme.primary)
    }

    private var header: some View {
        let modules = model.panelModules
        // Tabs fill the space left of the notch; any that don't fit continue right of it, so none
        // hides under the camera.
        let leftCount = modules.count > 1 ? min(modules.count, Self.tabsFitting(sideWidth: sideWidth)) : modules.count
        return HStack(spacing: Self.tabSpacing) {
            moduleSwitcher(Array(modules.prefix(leftCount)), showsTitle: modules.count == 1)
            // Keep the header's controls out from under the physical notch.
            Spacer(minLength: layout.centerGap + 2 * Self.notchClearance)
            moduleSwitcher(Array(modules.dropFirst(leftCount)), showsTitle: false)
            Menu {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .notchiOpenSettings, object: nil)
                }
                Divider()
                Button("Quit Notchi") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private static let tabSize: CGFloat = 26
    private static let tabSpacing: CGFloat = 4
    /// Clear space between the header's controls and the notch on each side.
    private static let notchClearance: CGFloat = 8

    /// Room for controls on one side of the notch.
    private var sideWidth: CGFloat {
        (layout.size.width - layout.centerGap) / 2 - (layout.horizontalInset + 12) - Self.notchClearance
    }

    /// How many tab buttons fit in `sideWidth` (at least one).
    static func tabsFitting(sideWidth: CGFloat) -> Int {
        max(1, Int((sideWidth + tabSpacing) / (tabSize + tabSpacing)))
    }

    @ViewBuilder
    private func moduleSwitcher(_ modules: [any NotchModule], showsTitle: Bool) -> some View {
        if !showsTitle {
            ForEach(modules, id: \.id) { module in
                Button {
                    withAnimation(Motion.content) { model.selectedModuleID = module.id }
                } label: {
                    Image(systemName: module.symbol)
                }
                .buttonStyle(NotchIconButtonStyle(isSelected: module.id == model.selectedModule?.id))
                .help(module.title)
            }
        } else if let module = modules.first {
            Text(module.title)
                .font(Theme.caption)
                .foregroundStyle(Theme.secondary)
        }
    }
}

#Preview("Expanded content") {
    NotchPreviewStage(model: .preview(.expanded, style: .notch))
}
