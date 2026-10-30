import SwiftUI

/// The two slots either side of the notch (or the island's center gap), plus an optional
/// full-width row below the notch when the live activity asks for one.
struct CompactContentView: View {
    let module: any NotchModule
    let layout: NotchLayout
    @AppStorage(Preferences.Key.compactAlignment) private var alignment = CompactAlignment.center

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                module.compactLeading()
                    .compactSlot(.leading, alignment: alignment)
                Color.clear
                    .frame(width: layout.centerGap)
                module.compactTrailing()
                    .compactSlot(.trailing, alignment: alignment)
            }
            .frame(height: layout.headerHeight)
            .environment(\.compactAlignment, alignment)

            if layout.size.height > layout.headerHeight + layout.bottomLip, let below = module.compactBelow() {
                below
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, layout.horizontalInset)
        .frame(height: layout.size.height, alignment: .top)
        .foregroundStyle(Theme.primary)
    }
}

/// Where live activity content sits in the slots beside the notch.
enum CompactAlignment: String, CaseIterable, Identifiable {
    /// In the middle of each slot.
    case center
    /// Against the surface's outer sides, with `Metrics.compactEdgeInset` of padding.
    case edges

    var id: Self { self }

    var title: String {
        switch self {
        case .center: "Centered"
        case .edges: "Edges"
        }
    }
}

extension EnvironmentValues {
    /// The compact layout in effect, so slot content that pins itself can tell it's already pinned.
    @Entry var compactAlignment: CompactAlignment = .center
}

extension View {
    /// Fills one compact slot, placing the content per the user's layout setting.
    func compactSlot(_ edge: HorizontalEdge, alignment: CompactAlignment) -> some View {
        let pinned = alignment == .edges
        return frame(maxWidth: .infinity, alignment: pinned ? (edge == .leading ? .leading : .trailing) : .center)
            .padding(edge == .leading ? .leading : .trailing, pinned ? Metrics.compactEdgeInset : 0)
    }
}

#Preview("Compact content") {
    NotchPreviewStage(model: .preview(.compact, style: .notch))
}
