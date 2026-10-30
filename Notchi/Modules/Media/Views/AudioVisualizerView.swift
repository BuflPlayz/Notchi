import SwiftUI

/// The compact-mode bars that dance while music plays.
///
/// With `levels` (from `AudioLevelMonitor`), the bars follow the actual audio. Without them
/// (permission not granted, setting off, previews), they fall back to layered sine waves eased
/// between ~8 updates a second. Either way nothing ticks while paused.
struct AudioVisualizerView: View {
    var isPlaying: Bool
    var color: Color
    var levels: [Double]? = nil
    var barCount = 4
    var height: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let levels, isPlaying, !reduceMotion {
            bars(levels)
                .animation(.linear(duration: 0.05), value: levels)
                .accessibilityHidden(true)
        } else {
            synthetic
        }
    }

    private func bars(_ levels: [Double]) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: max(3, (index < levels.count ? levels[index] : 0) * height))
            }
        }
        .frame(height: height)
    }

    private var synthetic: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying || reduceMotion)) { context in
            let levels = syntheticLevels(at: context.date)
            bars(levels)
                .animation(.easeInOut(duration: 0.14), value: levels)
        }
        .accessibilityHidden(true)
    }

    private func syntheticLevels(at date: Date) -> [Double] {
        guard isPlaying, !reduceMotion else {
            return Array(repeating: isPlaying ? 0.55 : 0.22, count: barCount)
        }
        let time = date.timeIntervalSinceReferenceDate
        return (0..<barCount).map { bar in
            let offset = Double(bar)
            let fast = sin(time * (5.3 + offset * 1.7) + offset * 1.3) * 0.5 + 0.5
            let slow = sin(time * (2.1 + offset * 0.9) + offset) * 0.5 + 0.5
            return 0.25 + 0.75 * (fast * 0.65 + slow * 0.35)
        }
    }
}

#Preview("Visualizer") {
    HStack(spacing: 24) {
        AudioVisualizerView(isPlaying: true, color: .pink)
        AudioVisualizerView(isPlaying: false, color: .pink)
        AudioVisualizerView(isPlaying: true, color: .white, levels: [0.9, 0.5, 0.7, 0.3])
    }
    .padding(24)
    .background(Theme.surface)
}
