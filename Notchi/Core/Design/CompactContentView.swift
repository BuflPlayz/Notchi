import SwiftUI

/// The two slots either side of the notch (or the island's center gap), plus an optional
/// full-width row below the notch when the live activity asks for one.
struct CompactContentView: View {
    let module: any NotchModule
    let layout: NotchLayout

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                module.compactLeading()
                    .frame(maxWidth: .infinity)
                Color.clear
                    .frame(width: layout.centerGap)
                module.compactTrailing()
                    .frame(maxWidth: .infinity)
            }
            .frame(height: layout.headerHeight)

            if layout.size.height > layout.headerHeight, let below = module.compactBelow() {
                below
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, layout.horizontalInset)
        .frame(height: layout.size.height, alignment: .top)
        .foregroundStyle(Theme.primary)
    }
}

#Preview("Compact content") {
    NotchPreviewStage(model: .preview(.compact, style: .notch))
}
