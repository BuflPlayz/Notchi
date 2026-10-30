import Foundation

/// Source of Clock app timer and stopwatch state.
@MainActor
protocol ClockActivityProvider: AnyObject {
    var onUpdate: ((ClockSnapshot) -> Void)? { get set }
    func start()
    func stop()
}

/// Reads the Clock app's state from `mobiletimerd`'s preferences domain and observes it.
///
/// There's no public API for Clock timers. The daemon keeps them in the `com.apple.mobiletimerd`
/// preferences domain, which any non-sandboxed app can read without a permission prompt. Reads go
/// through `cfprefsd`, so they're current the instant Clock changes something, unlike the plist on
/// disk, which lags by seconds. Key-value observing on the suite reports changes made by other
/// processes, so nothing is polled.
@MainActor
final class MobileTimerClockProvider: NSObject, ClockActivityProvider {
    var onUpdate: ((ClockSnapshot) -> Void)?

    private static let domain = "com.apple.mobiletimerd"
    private static let keys = ["MTTimers", "MTStopwatches"]

    private let defaults = UserDefaults(suiteName: MobileTimerClockProvider.domain)
    private var isObserving = false

    func start() {
        guard let defaults, !isObserving else { return }
        for key in Self.keys {
            defaults.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
        isObserving = true
        publish()
    }

    func stop() {
        guard let defaults, isObserving else { return }
        for key in Self.keys {
            defaults.removeObserver(self, forKeyPath: key)
        }
        isObserving = false
    }

    nonisolated override func observeValue(
        forKeyPath keyPath: String?, of object: Any?,
        change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        // KVO for external changes can arrive on any thread.
        Task { @MainActor [weak self] in self?.publish() }
    }

    private func publish() {
        let snapshot = ClockSnapshot(
            timersValue: defaults?.object(forKey: "MTTimers"),
            stopwatchesValue: defaults?.object(forKey: "MTStopwatches")
        )
        onUpdate?(snapshot)
    }
}

/// In-memory provider for previews and tests.
@MainActor
final class MockClockProvider: ClockActivityProvider {
    var onUpdate: ((ClockSnapshot) -> Void)?
    private(set) var snapshot: ClockSnapshot

    init(snapshot: ClockSnapshot = .sample) {
        self.snapshot = snapshot
    }

    func start() { onUpdate?(snapshot) }
    func stop() {}

    func update(_ newSnapshot: ClockSnapshot) {
        snapshot = newSnapshot
        onUpdate?(newSnapshot)
    }
}

extension ClockSnapshot {
    /// A running 25-minute focus timer and a running stopwatch.
    static var sample: ClockSnapshot {
        ClockSnapshot(
            timers: [ClockTimer(id: "focus", title: "Focus", duration: 1500, state: .running(fireDate: Date().addingTimeInterval(1121)))],
            stopwatch: ClockStopwatch(id: "sw", state: .running(since: Date().addingTimeInterval(-95), offset: 0), lapCount: 0)
        )
    }
}
