import AppKit
import SwiftUI

/// Timers and the stopwatch from Apple's Clock app, live in the notch.
///
/// Compact: a progress ring and the countdown (or the stopwatch's elapsed time). Expanded: the
/// featured timer and the stopwatch. When a timer ends, a short "done" toast shows. Clock's timers
/// can't be controlled from outside the app, so tapping opens Clock.
@MainActor
@Observable
final class ClockModule: NotchModule {
    let id = "clock"
    let title = "Clock"
    let symbol = "timer"

    private(set) var snapshot = ClockSnapshot()
    /// A timer that just reached zero, shown briefly as a toast.
    private(set) var finishedTimer: ClockTimer?
    private(set) var liveActivity: LiveActivity?

    @ObservationIgnored private let provider: ClockActivityProvider
    @ObservationIgnored private let toastDuration: Duration
    @ObservationIgnored private var fireTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesObserver: NSObjectProtocol?

    init(provider: ClockActivityProvider, toastDuration: Duration = .seconds(5)) {
        self.provider = provider
        self.toastDuration = toastDuration
    }

    func start() {
        provider.onUpdate = { [weak self] snapshot in self?.apply(snapshot) }
        provider.start()
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLiveActivity() }
        }
    }

    func stop() {
        provider.stop()
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
        preferencesObserver = nil
        fireTask?.cancel()
        toastTask?.cancel()
    }

    func openClockApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: NotchModule views

    func compactLeading() -> AnyView {
        AnyView(ClockCompactLeading(module: self))
    }

    func compactTrailing() -> AnyView {
        AnyView(ClockCompactTrailing(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(ClockSettingsView(module: self))
    }

    func expandedView() -> AnyView {
        AnyView(ClockExpandedView(module: self))
    }

    // MARK: State

    private func apply(_ newSnapshot: ClockSnapshot) {
        snapshot = newSnapshot
        scheduleNextFire()
        updateLiveActivity()
    }

    /// Wakes up exactly when the next running timer ends. The daemon updates its state around the
    /// same moment, but the toast shouldn't wait for that.
    private func scheduleNextFire() {
        fireTask?.cancel()
        let next = snapshot.timers
            .compactMap { timer -> (ClockTimer, Date)? in
                if case .running(let fireDate) = timer.state { return (timer, fireDate) }
                return nil
            }
            .min { $0.1 < $1.1 }
        guard let (timer, fireDate) = next else { return }
        fireTask = Task { [weak self] in
            let delay = fireDate.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            self.timerFinished(timer)
        }
    }

    private func timerFinished(_ timer: ClockTimer) {
        finishedTimer = timer
        snapshot.timers.removeAll { $0.id == timer.id }
        updateLiveActivity()
        toastTask?.cancel()
        let duration = toastDuration
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            self.finishedTimer = nil
            self.updateLiveActivity()
        }
    }

    private func updateLiveActivity() {
        let priority: LiveActivity.Priority?
        if finishedTimer != nil {
            priority = .transient
        } else if snapshot.primaryTimer?.isRunning == true || snapshot.stopwatch?.isRunning == true {
            priority = .active
        } else if !snapshot.isEmpty && Preferences.clockShowsPaused {
            priority = .ambient
        } else {
            priority = nil
        }
        // Countdowns need more room than an icon: "44:41", or "1:02:05" past an hour.
        let longest = max(snapshot.primaryTimer?.duration ?? 0, snapshot.stopwatch?.elapsed(at: Date()) ?? 0)
        let needed: CGFloat = longest >= 3600 ? 58 : 46
        liveActivity = priority.map { LiveActivity(priority: $0, sideWidth: max(Preferences.compactSideWidth, needed)) }
    }
}
