import AppKit
import SwiftUI

/// Mac activity in the notch: the volume and brightness HUD (replacing the system's), battery
/// with plug-in and low-battery toasts, and Focus changes. The expanded page shows battery and
/// Focus status with volume and brightness sliders.
@MainActor
@Observable
final class SystemModule: NotchModule {
    let id = "system"
    let title = "System"
    let symbol = "slider.horizontal.3"

    private(set) var battery: BatteryState?
    private(set) var volume = VolumeState(level: 0, isMuted: false, canChange: false)
    private(set) var brightness: Double?
    private(set) var focus = FocusState.inactive
    private(set) var toast: SystemToast?
    private(set) var liveActivity: LiveActivity?
    /// True while Notchi owns the volume and brightness keys.
    private(set) var isReplacingHUD = false

    let permission = AccessibilityPermission.shared

    @ObservationIgnored private let batteryMonitor = BatteryMonitor()
    @ObservationIgnored private let volumeController = VolumeController()
    @ObservationIgnored private let brightnessController = BrightnessController()
    @ObservationIgnored private let keyInterceptor = MediaKeyInterceptor()
    @ObservationIgnored private let focusMonitor = FocusMonitor()
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesObserver: NSObjectProtocol?
    @ObservationIgnored private var hasVolumeReading = false
    @ObservationIgnored private var hasFocusReading = false
    /// False while the module is disabled in Settings: nothing may start the key tap or Focus reading.
    @ObservationIgnored private var isActive = false

    func start() {
        guard !isActive else { return }
        isActive = true
        batteryMonitor.onChange = { [weak self] state in self?.batteryChanged(state) }
        volumeController.onChange = { [weak self] state in self?.volumeChanged(state) }
        focusMonitor.onChange = { [weak self] state in self?.focusChanged(state) }
        keyInterceptor.handler = { [weak self] key, fine in self?.handle(key, fine: fine) ?? false }

        batteryMonitor.start()
        volumeController.start()
        brightness = brightnessController.level
        observePermission()
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePermissionGatedFeatures() }
        }
        updatePermissionGatedFeatures()
    }

    func stop() {
        isActive = false
        batteryMonitor.stop()
        volumeController.stop()
        keyInterceptor.stop()
        isReplacingHUD = false
        focusMonitor.stop()
        hasFocusReading = false
        hasVolumeReading = false
        toastTask?.cancel()
        toast = nil
        liveActivity = nil
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
        preferencesObserver = nil
    }

    // MARK: Actions (expanded page)

    func setVolume(_ level: Double) {
        volumeController.setLevel(level)
    }

    func toggleMute() {
        volumeController.setMuted(!volume.isMuted)
    }

    func setBrightness(_ level: Double) {
        if brightnessController.setLevel(level) { brightness = level }
    }

    func refreshBrightness() {
        brightness = brightnessController.level
    }

    func requestAccessibility() {
        permission.request()
    }

    // MARK: NotchModule views

    func compactLeading() -> AnyView { AnyView(SystemCompactLeading(module: self)) }
    func compactTrailing() -> AnyView { AnyView(SystemCompactTrailing(module: self)) }
    func compactBelow() -> AnyView? { AnyView(SystemCompactBelow(module: self)) }
    func settingsView() -> AnyView? {
        AnyView(SystemSettingsView(module: self))
    }

    func expandedView() -> AnyView { AnyView(SystemExpandedView(module: self)) }

    // MARK: Permission-gated features

    private func observePermission() {
        withObservationTracking {
            _ = permission.isGranted
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.updatePermissionGatedFeatures()
                self.observePermission()
            }
        }
    }

    /// The key tap and Focus reading need Accessibility; start them once it's granted.
    private func updatePermissionGatedFeatures() {
        guard isActive else { return }
        let granted = permission.isGranted
        if granted && Preferences.replaceSystemHUD {
            if !keyInterceptor.isRunning { keyInterceptor.start() }
        } else if keyInterceptor.isRunning {
            keyInterceptor.stop()
        }
        isReplacingHUD = keyInterceptor.isRunning

        if granted && Preferences.focusAlerts {
            if !hasFocusReading {
                focusMonitor.start()          // reads the current state synchronously…
                hasFocusReading = true        // …which is the baseline, not a change to announce
            }
        } else {
            focusMonitor.stop()
            hasFocusReading = false
        }
    }

    // MARK: Keys

    /// Applies a volume or brightness key. Returns false to let the system handle it instead.
    private func handle(_ key: MediaKeyEvent.Key, fine: Bool) -> Bool {
        switch key {
        case .volumeUp, .volumeDown:
            guard volume.canChange else { return false }
            let up = key == .volumeUp
            // Like macOS: raising from mute starts from the current level, unmuted.
            let level = LevelStep.next(from: volume.level, up: up, fine: fine)
            volumeController.setLevel(level)
            if up && volume.isMuted { volumeController.setMuted(false) }
            playVolumeFeedback()
            // The volume listener shows the HUD on change; show it here too so presses at 0% or
            // 100% (no change) still give feedback.
            show(.volume(level: level, isMuted: volume.isMuted && !up), force: true)
            return true
        case .mute:
            guard volume.canChange else { return false }
            volumeController.setMuted(!volume.isMuted)
            return true
        case .brightnessUp, .brightnessDown:
            guard brightnessController.canChange, let current = brightnessController.level else { return false }
            let level = LevelStep.next(from: current, up: key == .brightnessUp, fine: fine)
            setBrightness(level)
            show(.brightness(level: level), force: true)
            return true
        }
    }

    /// The system's "pop" when "Play feedback when volume is changed" is on.
    private func playVolumeFeedback() {
        guard UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.sound.beep.feedback"] as? Int == 1 else { return }
        NSSound(contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff", byReference: true)?.play()
    }

    // MARK: State changes

    private func batteryChanged(_ state: BatteryState?) {
        let previous = battery
        battery = state
        if Preferences.batteryAlerts, let toast = BatteryAlerts.toast(from: previous, to: state) {
            show(toast)
        }
    }

    private func volumeChanged(_ state: VolumeState) {
        volume = state
        // The first reading is startup, not a change. While the system HUD is in charge, don't double it.
        defer { hasVolumeReading = true }
        guard hasVolumeReading, isReplacingHUD else { return }
        show(.volume(level: state.level, isMuted: state.isMuted), force: true)
    }

    private func focusChanged(_ state: FocusState) {
        focus = state
        guard hasFocusReading, Preferences.focusAlerts else { return }
        show(.focus(state))
    }

    #if DEBUG
    /// Shows the HUD without pressing keys (debug command `hud:volume:0.6`, `hud:brightness:0.3`, `hud:mute`).
    func showDebugHUD(_ spec: String) {
        let parts = spec.split(separator: ":")
        let level = parts.count > 1 ? Double(parts[1]) ?? 0.6 : 0.6
        switch parts.first {
        case "brightness": show(.brightness(level: level), force: true)
        case "mute": show(.volume(level: level, isMuted: true), force: true)
        default: show(.volume(level: level, isMuted: false), force: true)
        }
    }
    #endif

    // MARK: Toasts

    /// Shows a toast as a transient live activity. `force` lets a HUD update replace itself on
    /// every key press, extending its time.
    private func show(_ newToast: SystemToast, force: Bool = false) {
        guard force || newToast != toast else { return }
        let isHUD = newToast.kind == .volume || newToast.kind == .brightness
        if newToast.isSameKind(as: toast) {
            // One spring for the whole update, so the bar, the rolling digits and the icon move
            // together, and a held key retargets smoothly instead of stepping.
            withAnimation(Motion.hud) { toast = newToast }
        } else {
            toast = newToast
        }
        let activity = LiveActivity(
            priority: .transient,
            sideWidth: max(Preferences.compactSideWidth, newToast.sideWidth),
            showsInFullScreen: isHUD,
            belowHeight: newToast.belowHeight
        )
        if liveActivity != activity { liveActivity = activity }
        toastTask?.cancel()
        let duration = newToast.duration
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            self.toast = nil
            self.liveActivity = nil
        }
    }
}
