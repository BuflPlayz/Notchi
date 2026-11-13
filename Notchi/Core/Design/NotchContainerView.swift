import SwiftUI

extension Notification.Name {
    /// Posted to open the Settings window (SwiftUI's `openSettings` lives in the view hierarchy).
    static let notchiOpenSettings = Notification.Name("dev.notchi.openSettings")
}

/// Root view of the panel: the glass surface plus whichever content the state calls for.
///
/// The surface is one view whose frame and corner radii animate between layouts, so every
/// transition (idle ↔ compact ↔ expanded) is a single continuous, interruptible spring.
struct NotchContainerView: View {
    let model: NotchViewModel
    @AppStorage(Preferences.Key.islandVisibleWhenIdle) private var islandVisibleWhenIdle = Preferences.Default.islandVisibleWhenIdle
    @AppStorage(Preferences.Key.glassClarity) private var glassClarity = Preferences.Default.glassClarity
    @AppStorage(Preferences.Key.glassStyle) private var glassStyle = GlassStyle.clear
    @AppStorage(Preferences.Key.notchBlend) private var notchBlend = Preferences.Default.notchBlend
    @AppStorage(Preferences.Key.edgeHighlight) private var edgeHighlight = Preferences.Default.edgeHighlight

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let layout = model.layout
        let shape = NotchShape(style: model.geometry.style, topRadius: layout.topRadius, bottomRadius: layout.bottomRadius)

        ZStack(alignment: .top) {
            surface(layout: layout, shape: shape)
                .padding(.top, layout.topInset)
            satellites(layout: layout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.notchNamespace, reduceMotion ? nil : namespace)
        .environment(\.colorScheme, .dark)
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

    private func surface(layout: NotchLayout, shape: NotchShape) -> some View {
        content(layout: layout)
            .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
            .background {
                NotchSurface(
                    shape: shape,
                    notch: model.geometry.style == .notch ? model.geometry.idleSize : nil,
                    clarity: glassClarity / 100,
                    glass: glassStyle,
                    blend: notchBlend * (model.state == .expanded ? Metrics.Notch.expandedBlendScale : 1),
                    tint: surfaceTint
                )
                .animation(Motion.content, value: surfaceTint)
            }
            .clipShape(shape)
            .overlay { NotchRim(shape: shape, style: model.geometry.style, brightness: rimBrightness, notchFade: rimFade(layout: layout)) }
            .swapPulse(trigger: reduceMotion ? 0 : model.swapCount)
            .contentShape(shape)
            .background {
                if model.geometry.style == .island && model.state == .expanded {
                    IslandShadow(shape: shape)
                        .transition(.opacity)
                }
            }
            .opacity(isHiddenAtRest ? 0 : 1)
            .animation(Motion.content, value: isHiddenAtRest)
            // Only the surface opens the panel; the bubbles beside it swap instead.
            .simultaneousGesture(TapGesture().onEnded {
                if model.state != .expanded { model.expandNow() }
            })
    }

    /// Other live activities, in detached bubbles either side of the compact surface.
    private func satellites(layout: NotchLayout) -> some View {
        ForEach(model.visibleSatellites, id: \.module.id) { satellite in
            SatelliteBubble(module: satellite.module, diameter: layout.satelliteDiameter) {
                model.bringToFront(satellite.module.id)
            }
            // Placed with padding, not an offset: the warp's stretch anchors on the layout frame,
            // which has to be the bubble's own.
            .padding(satellite.side == .leading ? .trailing : .leading, 2 * layout.satelliteCenterOffset)
            .padding(.top, layout.satelliteTop)
            .transition(Motion.satelliteTransition(
                side: satellite.side,
                travel: Metrics.Satellite.gap + layout.satelliteDiameter * Metrics.Satellite.absorbTravel,
                reduceMotion: reduceMotion
            ))
        }
    }

    @ViewBuilder
    private func content(layout: NotchLayout) -> some View {
        ZStack(alignment: .top) {
            switch model.state {
            case .idle:
                Color.clear
            case .compact:
                // Empty while closed for a reopen: the old activity leaves, and the new one comes in as it opens.
                if let module = model.compactModule {
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

    /// Invisible at rest while a full-screen app is in front, or with "Show the island at rest" off
    /// (hovering its spot still opens it in that case).
    private var isHiddenAtRest: Bool {
        guard model.state == .idle else { return false }
        return model.isSuppressed || (model.geometry.style == .island && !islandVisibleWhenIdle)
    }

    /// The outline fades out as the notch closes into the hardware, so it never lingers along the
    /// notch's edge while the spring settles. The island keeps it: its capsule stays visible at rest.
    private var rimBrightness: Double {
        model.geometry.style == .notch && model.state == .idle ? 0 : edgeHighlight / 100
    }

    /// The color the activity in the middle asks for, only while the notch shows it.
    private var surfaceTint: Color? {
        model.state == .compact ? model.compactModule?.liveActivity?.surfaceTint : nil
    }

    /// Notch style: the outline fades before the camera housing when the surface barely reaches below it.
    private func rimFade(layout: NotchLayout) -> NotchRimFade? {
        guard model.geometry.style == .notch else { return nil }
        return NotchRimFade(notch: model.geometry.idleSize, shapeWidth: layout.size.width, height: layout.size.height)
    }
}

/// The expanded island's shadow (it floats over content instead of blending into hardware), cast
/// by its outline alone. A `.shadow` on the surface itself would render the glass and everything on
/// it a second time, offscreen, whenever any of it redraws: the visualizer, a mascot, the clock.
private struct IslandShadow: View {
    let shape: NotchShape

    var body: some View {
        shape
            .fill(.black)
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            // Only the part outside the outline: the glass is see-through.
            .mask {
                Rectangle()
                    .padding(-60)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
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
