import SwiftUI

/// The two slots either side of the notch (or the island's center gap).
struct CompactContentView: View {
    let module: any NotchModule
    let layout: NotchLayout

    var body: some View {
        HStack(spacing: 0) {
            module.compactLeading()
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(width: layout.centerGap)
            module.compactTrailing()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, layout.horizontalInset)
        .frame(height: layout.size.height)
        .foregroundStyle(Theme.primary)
    }
}

#Preview("Compact content") {
    NotchPreviewStage(model: .preview(.compact, style: .notch))
}
