import AppKit

/// Whether anything is recording (or sharing) the screen.
///
/// The window server knows: `SLSIsScreenWatcherPresent` (private SkyLight, SIP-safe, loaded with
/// `dlsym`) is true exactly while the screen is captured, from the Screenshot toolbar, QuickTime,
/// ScreenCaptureKit apps or a call's screen sharing (measured on macOS 27.2). No notification
/// announces it (none of SkyLight's notify types fired when a recording started), so the monitor
/// asks once a second. A check costs about 28 µs.
@MainActor
final class ScreenCaptureMonitor {
    var onChange: ((Bool) -> Void)?
    /// Every check while recording, so users can refresh what they derive (the time's width).
    var onTick: (() -> Void)?
    private(set) var isCapturing = false

    private var timer: Timer?

    private static let isScreenWatcherPresent: (@convention(c) () -> Bool)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "SLSIsScreenWatcherPresent")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) () -> Bool).self)
    }()

    /// False if this macOS doesn't have the call, so the feature can say it's unavailable.
    static var isAvailable: Bool { isScreenWatcherPresent != nil }

    func start() {
        guard timer == nil, Self.isAvailable else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.3
        self.timer = timer
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isCapturing = false
    }

    private func check() {
        let capturing = Self.isScreenWatcherPresent?() ?? false
        if capturing { onTick?() }
        guard capturing != isCapturing else { return }
        isCapturing = capturing
        onChange?(capturing)
    }

    // MARK: Stopping

    static let screenshotBundleID = "com.apple.screencaptureui"

    /// A recording from the Screenshot toolbar (⇧⌘5, or QuickTime's New Screen Recording) can be
    /// stopped with its own shortcut, ⌃⌘⎋. Posting it needs Accessibility.
    static var canStopRecording: Bool {
        AXIsProcessTrusted() && !NSRunningApplication.runningApplications(withBundleIdentifier: screenshotBundleID).isEmpty
    }

    static func stopRecording() {
        guard canStopRecording else { return }
        let escape: CGKeyCode = 53
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: escape, keyDown: down)
            event?.flags = [.maskCommand, .maskControl]
            event?.post(tap: .cghidEventTap)
        }
    }
}
