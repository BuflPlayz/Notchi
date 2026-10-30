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
        HStack(spacing: 4) {
            moduleSwitcher
            // Keep the header's controls out from under the physical notch.
            Spacer(minLength: layout.centerGap + 16)
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

    @ViewBuilder
    private var moduleSwitcher: some View {
        let modules = model.registry.modules
        if modules.count > 1 {
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
