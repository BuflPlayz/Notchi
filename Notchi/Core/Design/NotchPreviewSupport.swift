import SwiftUI

// Fixtures for #Preview blocks: realistic screens, a ready-made view model, and a stage
// that paints a fake menu bar (plus the hardware notch) behind the surface.

extension NotchGeometry {
    /// 14" MacBook Pro: 1512×982 pt, 32 pt notch.
    static let previewNotch = NotchGeometry.make(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32,
        topLeftArea: CGRect(x: 0, y: 950, width: 662, height: 32),
        topRightArea: CGRect(x: 850, y: 950, width: 662, height: 32),
        menuBarHeight: 32
    )

    /// 27" external display: 2560×1440 pt, 24 pt menu bar, no notch.
    static let previewIsland = NotchGeometry.make(
        screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        safeAreaTop: 0,
        topLeftArea: nil,
        topRightArea: nil,
        menuBarHeight: 24
    )
}

extension NotchViewModel {
    /// A view model frozen in `state`, with the media module playing a sample track.
    static func preview(_ state: NotchState, style: NotchGeometry.Style) -> NotchViewModel {
        let registry = ModuleRegistry()
        let media = MediaModule(provider: MockNowPlayingProvider())
        registry.register(media)
        media.start()
        let model = NotchViewModel(geometry: style == .notch ? .previewNotch : .previewIsland, registry: registry)
        model.setStateForPreview(state)
        return model
    }
}

/// Wallpaper + menu bar strip behind the surface, sized like the real panel area.
struct NotchPreviewStage: View {
    let model: NotchViewModel

    var body: some View {
        let geometry = model.geometry
        ZStack(alignment: .top) {
            LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: geometry.menuBarHeight)
            if geometry.style == .notch {
                // Stand-in for the physical notch.
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                    .fill(.black)
                    .frame(width: geometry.idleSize.width, height: geometry.idleSize.height)
            }
            NotchContainerView(model: model)
        }
        .frame(width: 620, height: 260)
    }
}
