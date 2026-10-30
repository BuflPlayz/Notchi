import Foundation

/// A timer from Apple's Clock app.
struct ClockTimer: Equatable, Sendable, Identifiable {
    enum State: Equatable, Sendable {
        case running(fireDate: Date)
        case paused(remaining: TimeInterval)
    }

    let id: String
    /// The user's label; nil for unnamed timers.
    var title: String?
    var duration: TimeInterval
    var state: State

    func remaining(at date: Date) -> TimeInterval {
        switch state {
        case .running(let fireDate): max(fireDate.timeIntervalSince(date), 0)
        case .paused(let remaining): remaining
        }
    }

    /// 0 at the start, 1 when done.
    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(1 - remaining(at: date) / duration, 0), 1)
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }
}

/// The stopwatch from Apple's Clock app.
struct ClockStopwatch: Equatable, Sendable {
    enum State: Equatable, Sendable {
        /// Running since `since`, after `offset` seconds accumulated before.
        case running(since: Date, offset: TimeInterval)
        case paused(elapsed: TimeInterval)
    }

    let id: String
    var state: State
    var lapCount: Int

    func elapsed(at date: Date) -> TimeInterval {
        switch state {
        case .running(let since, let offset): offset + max(date.timeIntervalSince(since), 0)
        case .paused(let elapsed): elapsed
        }
    }

    /// The moment the stopwatch would have read 0:00 had it never paused, for `Text(timerInterval:)`.
    var virtualStart: Date? {
        if case .running(let since, let offset) = state { return since.addingTimeInterval(-offset) }
        return nil
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }
}

/// The Clock app's active timers and stopwatch, decoded from `mobiletimerd`'s preferences.
///
/// This is private, undocumented data (observed on macOS 27.2). Codes:
/// - `MTTimerState`: 1 stopped, 2 paused (remaining in `MTTimerTimeInterval`), 3 running (fire date in `MTTimerTimeDate`).
/// - `MTStopwatchState`: 1 paused or reset (elapsed in `MTStopwatchOffset`), 2 running (`MTStopwatchStartDate` + offset).
///
/// Anything unrecognized decodes to "nothing active", so a format change degrades quietly.
struct ClockSnapshot: Equatable, Sendable {
    var timers: [ClockTimer] = []
    var stopwatch: ClockStopwatch?

    var isEmpty: Bool { timers.isEmpty && stopwatch == nil }

    /// The timer to feature: running before paused, then soonest to finish.
    var primaryTimer: ClockTimer? {
        timers.min { lhs, rhs in
            if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
            return lhs.remaining(at: Date()) < rhs.remaining(at: Date())
        }
    }

    init(timers: [ClockTimer] = [], stopwatch: ClockStopwatch? = nil) {
        self.timers = timers
        self.stopwatch = stopwatch
    }

    /// Decodes the `MTTimers` and `MTStopwatches` preference values.
    init(timersValue: Any?, stopwatchesValue: Any?) {
        timers = Self.entries(timersValue, listKey: "MTTimers", entryKey: "$MTTimer").compactMap(Self.timer)
        stopwatch = Self.entries(stopwatchesValue, listKey: "MTStopwatches", entryKey: "$MTStopwatch").lazy.compactMap(Self.stopwatch).first
    }

    private static func entries(_ value: Any?, listKey: String, entryKey: String) -> [[String: Any]] {
        guard let container = value as? [String: Any], let list = container[listKey] as? [Any] else { return [] }
        return list.compactMap { ($0 as? [String: Any])?[entryKey] as? [String: Any] }
    }

    private static func timer(_ entry: [String: Any]) -> ClockTimer? {
        guard let id = entry["MTTimerID"] as? String, let stateCode = number(entry["MTTimerState"]) else { return nil }
        let fireTime = entry["MTTimerFireTime"] as? [String: Any]
        let state: ClockTimer.State
        switch Int(stateCode) {
        case 3:
            guard let fireDate = (fireTime?["$MTTimerDate"] as? [String: Any])?["MTTimerTimeDate"] as? Date else { return nil }
            state = .running(fireDate: fireDate)
        case 2:
            guard let remaining = number((fireTime?["$MTTimerTimeInterval"] as? [String: Any])?["MTTimerTimeInterval"]) else { return nil }
            state = .paused(remaining: remaining)
        default:
            return nil  // stopped
        }
        let title = (entry["MTTimerTitle"] as? String).flatMap { $0.isEmpty || $0 == "CURRENT_TIMER" ? nil : $0 }
        return ClockTimer(id: id, title: title, duration: number(entry["MTTimerDuration"]) ?? 0, state: state)
    }

    private static func stopwatch(_ entry: [String: Any]) -> ClockStopwatch? {
        guard let id = entry["MTStopwatchIdentifier"] as? String, let stateCode = number(entry["MTStopwatchState"]) else { return nil }
        let offset = number(entry["MTStopwatchOffset"]) ?? 0
        let lapCount = (entry["MTStopwatchLaps"] as? [Any])?.count ?? 0
        switch Int(stateCode) {
        case 2:
            guard let start = entry["MTStopwatchStartDate"] as? Date else { return nil }
            return ClockStopwatch(id: id, state: .running(since: start, offset: offset), lapCount: lapCount)
        case 1 where offset > 0:
            return ClockStopwatch(id: id, state: .paused(elapsed: offset), lapCount: lapCount)
        default:
            return nil  // reset
        }
    }

    /// Plist numbers arrive as NSNumber, but some are stored as strings.
    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
