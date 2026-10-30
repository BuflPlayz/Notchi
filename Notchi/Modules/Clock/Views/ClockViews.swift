import SwiftUI

/// Clock's timer orange.
private let clockAccent = Color.orange

// MARK: - Compact

/// Left slot: a ring showing the timer's progress, or a stopwatch glyph.
struct ClockCompactLeading: View {
    let module: ClockModule

    var body: some View {
        Group {
            if module.finishedTimer != nil {
                Image(systemName: "bell.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(clockAccent)
                    .symbolEffect(.bounce, options: .repeat(2), value: module.finishedTimer?.id)
            } else if let timer = module.snapshot.primaryTimer {
                TimerProgressRing(timer: timer, lineWidth: 2.5)
                    .frame(width: 16, height: 16)
            } else if module.snapshot.stopwatch != nil {
                Image(systemName: "stopwatch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(clockAccent)
            }
        }
        .notchMatchedGeometry(id: "clock.icon")
    }
}

/// Right slot: the live countdown (or stopwatch time), updated by SwiftUI itself.
struct ClockCompactTrailing: View {
    let module: ClockModule

    var body: some View {
        Group {
            if module.finishedTimer != nil {
                Text("Done")
            } else if let timer = module.snapshot.primaryTimer {
                TimerCountdownText(timer: timer)
            } else if let stopwatch = module.snapshot.stopwatch {
                StopwatchText(stopwatch: stopwatch)
            }
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(clockAccent)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - Building blocks

/// Counts down to the fire date without any timer of ours: `Text(timerInterval:)` redraws itself.
struct TimerCountdownText: View {
    let timer: ClockTimer

    var body: some View {
        switch timer.state {
        case .running(let fireDate):
            Text(timerInterval: Date()...max(fireDate, Date()), countsDown: true)
        case .paused(let remaining):
            Text(ClockFormat.duration(remaining))
                .opacity(0.6)
        }
    }
}

struct StopwatchText: View {
    let stopwatch: ClockStopwatch

    var body: some View {
        if let start = stopwatch.virtualStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
        } else {
            Text(ClockFormat.duration(stopwatch.elapsed(at: Date())))
                .opacity(0.6)
        }
    }
}

/// A circular progress ring for a timer. Ticks once a second, and only while running and on screen.
struct TimerProgressRing: View {
    let timer: ClockTimer
    var lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = 1 - timer.progress(at: timer.isRunning ? context.date : Date())
            ZStack {
                Circle().stroke(clockAccent.opacity(0.25), lineWidth: lineWidth)
                // Steps once a second, deliberately unanimated: a 1 s linear animation restarted every
                // second never ends, which keeps the panel redrawing at 120 Hz.
                Circle()
                    .trim(from: 0, to: remaining)
                    .stroke(clockAccent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

enum ClockFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        PlaybackProgressView.format(seconds.rounded(.up))
    }

    /// "25 min", "1 hr 30 min".
    static func label(for duration: TimeInterval) -> String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }
}

// MARK: - Expanded

/// The featured timer and the stopwatch, Clock-style: big light digits, orange accents.
struct ClockExpandedView: View {
    let module: ClockModule

    var body: some View {
        let snapshot = module.snapshot
        Group {
            if snapshot.isEmpty && module.finishedTimer == nil {
                emptyState
            } else {
                VStack(spacing: 10) {
                    if let finished = module.finishedTimer {
                        row(icon: AnyView(bell), title: finished.title ?? "Timer", subtitle: "Done", value: AnyView(Text("0:00")))
                    } else if let timer = snapshot.primaryTimer {
                        row(
                            icon: AnyView(TimerProgressRing(timer: timer).frame(width: 34, height: 34).notchMatchedGeometry(id: "clock.icon")),
                            title: timer.title ?? "Timer",
                            subtitle: timerSubtitle(timer, others: snapshot.timers.count - 1),
                            value: AnyView(TimerCountdownText(timer: timer))
                        )
                    }
                    if let stopwatch = snapshot.stopwatch {
                        row(
                            icon: AnyView(Image(systemName: "stopwatch").font(.system(size: 20, weight: .medium)).foregroundStyle(clockAccent).frame(width: 34, height: 34)),
                            title: "Stopwatch",
                            subtitle: stopwatch.isRunning ? (stopwatch.lapCount > 0 ? "Lap \(stopwatch.lapCount + 1)" : "Running") : "Paused",
                            value: AnyView(StopwatchText(stopwatch: stopwatch))
                        )
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: module.openClockApp)
        .help("Open Clock")
    }

    private func row(icon: AnyView, title: String, subtitle: String, value: AnyView) -> some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            value
                .font(.system(size: 30, weight: .light).monospacedDigit())
                .foregroundStyle(clockAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var bell: some View {
        Image(systemName: "bell.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(clockAccent)
            .frame(width: 34, height: 34)
    }

    private func timerSubtitle(_ timer: ClockTimer, others: Int) -> String {
        var parts = [timer.isRunning ? ClockFormat.label(for: timer.duration) : "Paused"]
        if others > 0 { parts.append("+\(others) more") }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        HStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.controlFill))
            VStack(alignment: .leading, spacing: 4) {
                Text("No timers running").font(Theme.title)
                Text("Start a timer or the stopwatch in Clock and it shows up here.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("Expanded · timer + stopwatch") {
    let module = ClockModule(provider: MockClockProvider())
    module.start()
    return ClockExpandedView(module: module)
        .frame(width: 408, height: 126)
        .padding()
        .background(Theme.surface)
        .foregroundStyle(Theme.primary)
}

#Preview("Expanded · empty") {
    let module = ClockModule(provider: MockClockProvider(snapshot: ClockSnapshot()))
    module.start()
    return ClockExpandedView(module: module)
        .frame(width: 408, height: 126)
        .padding()
        .background(Theme.surface)
        .foregroundStyle(Theme.primary)
}

#Preview("Compact") {
    let module = ClockModule(provider: MockClockProvider())
    module.start()
    return HStack(spacing: 40) {
        ClockCompactLeading(module: module)
        ClockCompactTrailing(module: module)
    }
    .padding(20)
    .background(Theme.surface)
}
