import SwiftUI

extension Notification.Name {
    /// Posted to open the Settings window (SwiftUI's `openSettings` lives in the view hierarchy).
    static let notchiOpenSettings = Notification.Name("dev.notchi.openSettings")
}

/// Root view of the panel: the black surface plus whichever content the state calls for.
///
/// The surface is one view whose frame and corner radii animate between layouts, so every
/// transition (idle ↔ compact ↔ expanded) is a single continuous, interruptible spring.
struct NotchContainerView: View {
    let model: NotchViewModel
    @AppStorage(Preferences.Key.islandVisibleWhenIdle) private var islandVisibleWhenIdle = true

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let layout = model.layout
        let shape = NotchShape(style: model.geometry.style, topRadius: layout.topRadius, bottomRadius: layout.bottomRadius)

        content(layout: layout)
            .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
            .background(Theme.surface)
            .clipShape(shape)
            .contentShape(shape)
            .shadow(color: .black.opacity(islandShadowOpacity), radius: 18, y: 8)
            .opacity(isHiddenAtRest ? 0 : 1)
            .animation(Motion.content, value: isHiddenAtRest)
            .padding(.top, layout.topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .environment(\.notchNamespace, reduceMotion ? nil : namespace)
            .environment(\.colorScheme, .dark)
            .simultaneousGesture(TapGesture().onEnded {
                if model.state != .expanded { model.expandNow() }
            })
            .onReceive(NotificationCenter.default.publisher(for: .notchiOpenSettings)) { _ in
                model.collapse()
                NSApp.activate()
                openSettings()
            }
            .contextMenu {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .notchiOpenSettings, object: nil)
                }
                Divider()
                Button("Quit Notchi") { NSApp.terminate(nil) }
            }
    }

    @ViewBuilder
    private func content(layout: NotchLayout) -> some View {
        ZStack(alignment: .top) {
            switch model.state {
            case .idle:
                Color.clear
            case .compact:
                if let module = model.registry.foreground {
                    CompactContentView(module: module, layout: layout)
                        .id(module.id)
                        .transition(Motion.contentTransition(reduceMotion: reduceMotion))
                }
            case .expanded:
                ExpandedContentView(model: model, layout: layout)
                    .transition(Motion.contentTransition(reduceMotion: reduceMotion))
            }
        }
    }

    /// "Show the island at rest" off: the resting capsule is invisible, though hovering its spot still opens it.
    private var isHiddenAtRest: Bool {
        model.geometry.style == .island && model.state == .idle && !islandVisibleWhenIdle
    }

    /// Only the expanded island casts a shadow: it floats over content instead of blending into hardware.
    private var islandShadowOpacity: Double {
        model.geometry.style == .island && model.state == .expanded ? 0.45 : 0
    }
}

#Preview("Notch · compact") {
    NotchPreviewStage(model: .preview(.compact, style: .notch))
}

#Preview("Notch · expanded") {
    NotchPreviewStage(model: .preview(.expanded, style: .notch))
}

#Preview("Island · idle") {
    NotchPreviewStage(model: .preview(.idle, style: .island))
}

#Preview("Island · compact") {
    NotchPreviewStage(model: .preview(.compact, style: .island))
}

#Preview("Island · expanded") {
    NotchPreviewStage(model: .preview(.expanded, style: .island))
}
