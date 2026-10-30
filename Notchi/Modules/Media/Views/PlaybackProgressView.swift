import SwiftUI

/// Progress bar with elapsed and remaining time. Drag or click to seek.
///
/// The position is extrapolated from the last report (see `NowPlayingInfo.elapsed(at:)`), and the
/// timeline only ticks while playing, and only while this view exists, i.e. when the panel is open.
struct PlaybackProgressView: View {
    let info: NowPlayingInfo
    let accent: Color
    let onSeek: (TimeInterval) -> Void

    /// Fraction under the cursor while dragging; nil otherwise.
    @State private var scrubFraction: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !info.isPlaying || scrubFraction != nil)) { context in
            let duration = info.duration ?? 0
            let elapsed = scrubFraction.map { $0 * duration } ?? info.elapsed(at: context.date)
            let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0

            VStack(spacing: 5) {
                bar(fraction: fraction, duration: duration)
                if duration > 0 {
                    HStack {
                        Text(Self.format(elapsed))
                        Spacer()
                        Text("-" + Self.format(duration - elapsed))
                    }
                    .font(Theme.caption.monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }

    private func bar(fraction: Double, duration: TimeInterval) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.controlFill)
                Capsule()
                    .fill(accent)
                    .frame(width: geometry.size.width * fraction)
            }
            .frame(height: scrubFraction == nil ? 4 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        scrubFraction = min(max(value.location.x / geometry.size.width, 0), 1)
                    }
                    .onEnded { _ in
                        if let scrubFraction { onSeek(scrubFraction * duration) }
                        scrubFraction = nil
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: scrubFraction == nil)
        }
        .frame(height: 12)
    }

    nonisolated static func format(_ seconds: TimeInterval) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(max(seconds, 0).rounded(.down)).formatted(.time(pattern: pattern))
    }
}

#Preview("Progress") {
    VStack(spacing: 20) {
        PlaybackProgressView(info: .sample, accent: .pink) { _ in }
        PlaybackProgressView(info: { var info = NowPlayingInfo.sample; info.isPlaying = false; return info }(), accent: .white) { _ in }
    }
    .frame(width: 300)
    .padding(24)
    .background(Theme.surface)
}
