import AppKit
import SwiftUI

/// An app recording audio that isn't a call (Voice Memos, QuickTime).
struct AudioRecording: Equatable {
    var appBundleID: String?
    var appName: String
    var since: Date
}

/// Recording in the notch, like the iPhone's red recording pill.
///
/// - **Screen:** while anything records or shares the screen, a pulsing red dot and the recording's
///   running time. The panel stops a Screenshot-toolbar recording (`ScreenCaptureMonitor`).
/// - **Microphone:** an app (not a call; `CallsModule` has those) recording audio: an orange mic and
///   the time. Found through Core Audio (`MicrophoneMonitor`), with no permission.
///
/// The screen comes first when both are on; the panel lists both.
@MainActor
@Observable
final class CaptureModule: NotchModule {
    let id = "recording"
    let title = "Recording"
    let symbol = "record.circle"

    /// When the screen recording started, while one runs.
    private(set) var screenSince: Date?
    private(set) var audio: AudioRecording?
    private(set) var liveActivity: LiveActivity?

    @ObservationIgnored private let screen = ScreenCaptureMonitor()
    @ObservationIgnored private let microphone = MicrophoneMonitor()
    @ObservationIgnored private var preferencesObserver: NSObjectProtocol?
    @ObservationIgnored private var isActive = false

    var showsInPanel: Bool { liveActivity != nil }

    func start() {
        guard !isActive else { return }
        isActive = true
        screen.onChange = { [weak self] capturing in self?.applyScreen(capturing) }
        screen.onTick = { [weak self] in self?.updateLiveActivity() }
        microphone.onChange = { [weak self] uses in self?.applyMicrophone(uses) }
        microphone.onTick = { [weak self] in self?.updateLiveActivity() }
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMonitors() }
        }
        updateMonitors()
    }

    func stop() {
        isActive = false
        screen.stop()
        microphone.stop()
        screenSince = nil
        audio = nil
        liveActivity = nil
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
        preferencesObserver = nil
    }

    /// A Screenshot-toolbar recording, which Notchi can stop. Read when the panel draws.
    var canStopScreen: Bool { screenSince != nil && ScreenCaptureMonitor.canStopRecording }

    func stopScreenRecording() {
        ScreenCaptureMonitor.stopRecording()
    }

    func showAudioApp() {
        CallApps.show(audio?.appBundleID)
    }

    // MARK: State

    func applyScreen(_ capturing: Bool) {
        withAnimation(Motion.content) { screenSince = capturing ? (screenSince ?? Date()) : nil }
        updateLiveActivity()
    }

    func applyMicrophone(_ uses: [MicrophoneUse]) {
        let recording = uses.first(where: CallApps.isRecording).map { use in
            AudioRecording(appBundleID: use.bundleID, appName: CallApps.name(for: use.bundleID), since: use.since)
        }
        if recording != audio { withAnimation(Motion.content) { audio = recording } }
        updateLiveActivity()
    }

    private func updateMonitors() {
        guard isActive else { return }
        if Preferences.recordingShowsScreen {
            screen.start()
        } else {
            screen.stop()
            applyScreen(false)
        }
        if Preferences.recordingShowsMicrophone {
            microphone.start()
        } else {
            microphone.stop()
            applyMicrophone([])
        }
    }

    private func updateLiveActivity() {
        let activity = (screenSince ?? audio?.since).map { since in
            let long = Date().timeIntervalSince(since) >= 3600 - 2
            return LiveActivity(priority: .active, sideWidth: max(Preferences.compactSideWidth, long ? CallMetrics.longTimeWidth : CallMetrics.timeWidth))
        }
        if activity != liveActivity { liveActivity = activity }
    }

    #if DEBUG
    /// Fakes recordings (debug commands `rec:screen`, `rec:audio`, `rec:off`).
    func showDebugRecording(_ command: String) {
        switch command {
        case "screen": applyScreen(true)
        case "audio":
            audio = AudioRecording(appBundleID: "com.apple.VoiceMemos", appName: "Voice Memos", since: Date())
            updateLiveActivity()
        case "off":
            applyScreen(false)
            applyMicrophone([])
        default: break
        }
    }
    #endif

    // MARK: NotchModule views

    func compactLeading() -> AnyView { AnyView(RecordingCompactLeading(module: self)) }
    func compactTrailing() -> AnyView { AnyView(RecordingCompactTrailing(module: self)) }
    func compactMinimal() -> AnyView { AnyView(RecordingGlyph(module: self)) }
    func expandedView() -> AnyView { AnyView(RecordingExpandedView(module: self)) }
    func settingsView() -> AnyView? { AnyView(RecordingSettingsView(module: self)) }
}
