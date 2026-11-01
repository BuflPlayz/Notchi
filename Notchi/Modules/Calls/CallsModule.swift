import AppKit
import SwiftUI

/// A call in progress.
struct OngoingCall: Equatable {
    /// The app the call is in (FaceTime, Zoom…); nil if Notchi can't tell.
    var appBundleID: String?
    var appName: String
    /// When its microphone came on.
    var since: Date
    /// A camera is on too.
    var isVideo = false
}

/// A call that just ended, shown briefly as a toast.
struct EndedCall: Equatable {
    var appName: String
    var duration: TimeInterval
}

/// Calls in the notch, like the iPhone's Dynamic Island.
///
/// - **On a call:** an app that calls (FaceTime, Phone, Zoom, Teams, Slack, Discord… and browsers,
///   for calls on the web) is using the microphone: a green phone (a camera when video is on) and the
///   call's running time. The panel has the system-wide microphone mute and a button that brings the
///   call's app forward. Found through Core Audio (`MicrophoneMonitor`), with no permission.
/// - **Incoming:** a FaceTime or iPhone call ringing takes the middle (`urgent`), with the caller's
///   name; the panel answers or declines it. Read from Notification Center's alert
///   (`IncomingCallMonitor`), which needs Accessibility.
/// - **Ended:** a short "Ended" toast.
@MainActor
@Observable
final class CallsModule: NotchModule {
    let id = "calls"
    let title = "Calls"
    let symbol = "phone.fill"

    private(set) var incoming: IncomingCall?
    private(set) var call: OngoingCall?
    private(set) var ended: EndedCall?
    private(set) var liveActivity: LiveActivity?
    private(set) var isMicrophoneMuted = false
    private(set) var canMuteMicrophone = false

    let permission = AccessibilityPermission.shared

    @ObservationIgnored private let microphone = MicrophoneMonitor()
    @ObservationIgnored private let mute = MicrophoneMute()
    @ObservationIgnored private let incomingMonitor = IncomingCallMonitor()
    @ObservationIgnored private let toastDuration: Duration
    @ObservationIgnored private let endDelay: Duration
    @ObservationIgnored private var endTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesObserver: NSObjectProtocol?
    @ObservationIgnored private var isActive = false

    /// - Parameter endDelay: How long a call's microphone may stay off before the call counts as
    ///   over. Apps briefly stop it when switching devices.
    init(toastDuration: Duration = .seconds(3), endDelay: Duration = .seconds(2)) {
        self.toastDuration = toastDuration
        self.endDelay = endDelay
    }

    /// Only while there's a call to show.
    var showsInPanel: Bool { incoming != nil || call != nil || ended != nil }

    func start() {
        guard !isActive else { return }
        isActive = true
        microphone.onChange = { [weak self] uses in self?.apply(uses) }
        microphone.onTick = { [weak self] in self?.refreshVideo() }
        microphone.start()
        mute.onChange = { [weak self] in
            guard let self else { return }
            self.isMicrophoneMuted = self.mute.isMuted
            self.canMuteMicrophone = self.mute.canMute
        }
        mute.start()
        incomingMonitor.onChange = { [weak self] call in self?.applyIncoming(call) }
        observePermission()
        updateIncomingMonitor()
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateIncomingMonitor()
                self.apply(self.microphone.uses)
            }
        }
    }

    func stop() {
        isActive = false
        microphone.stop()
        mute.stop()
        incomingMonitor.stop()
        endTask?.cancel()
        endTask = nil
        toastTask?.cancel()
        incoming = nil
        call = nil
        ended = nil
        liveActivity = nil
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
        preferencesObserver = nil
    }

    // MARK: Actions

    func answer() { incomingMonitor.answer() }
    func decline() { incomingMonitor.reject() }

    func toggleMicrophoneMute() {
        mute.setMuted(!isMicrophoneMuted)
    }

    func showCallApp() {
        CallApps.show(incoming?.appBundleID ?? call?.appBundleID)
    }

    func requestAccessibility() {
        permission.request()
    }

    // MARK: State

    /// The microphone's users changed: the first calling app is the call.
    func apply(_ uses: [MicrophoneUse]) {
        let calls = uses.filter { CallApps.isCall($0, includeBrowsers: Preferences.callsIncludeBrowsers) }
        if let current = call, let use = calls.first(where: { CallApps.appBundleID(for: $0) == current.appBundleID }) ?? calls.first {
            // Still on (or back within the grace period): keep the start time it had.
            endTask?.cancel()
            endTask = nil
            let bundleID = CallApps.appBundleID(for: use)
            if bundleID != current.appBundleID {
                call = OngoingCall(appBundleID: bundleID, appName: CallApps.name(for: bundleID), since: use.since, isVideo: Camera.isInUse())
            }
        } else if let use = calls.first {
            let bundleID = CallApps.appBundleID(for: use)
            toastTask?.cancel()
            ended = nil
            withAnimation(Motion.content) {
                call = OngoingCall(appBundleID: bundleID, appName: CallApps.name(for: bundleID), since: use.since, isVideo: Camera.isInUse())
            }
        } else if call != nil, endTask == nil {
            let delay = endDelay
            endTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                self.endTask = nil
                self.endCall()
            }
        }
        updateLiveActivity()
    }

    func applyIncoming(_ newCall: IncomingCall?) {
        guard newCall != incoming else { return }
        withAnimation(Motion.content) { incoming = newCall }
        if newCall != nil {
            toastTask?.cancel()
            ended = nil
        }
        updateLiveActivity()
    }

    private func endCall() {
        guard let finished = call else { return }
        call = nil
        let duration = Date().timeIntervalSince(finished.since)
        if Preferences.callsAnnounceEnd && duration >= 3 && incoming == nil {
            ended = EndedCall(appName: finished.appName, duration: duration)
            toastTask?.cancel()
            let toastDuration = toastDuration
            toastTask = Task { [weak self] in
                try? await Task.sleep(for: toastDuration)
                guard let self, !Task.isCancelled else { return }
                self.ended = nil
                self.updateLiveActivity()
            }
        }
        updateLiveActivity()
    }

    /// While on a call, a camera coming on (or off) switches the glyph.
    private func refreshVideo() {
        guard var current = call else { return }
        let video = Camera.isInUse()
        if video != current.isVideo {
            current.isVideo = video
            call = current
        }
        updateLiveActivity()  // past an hour the time needs more room
    }

    private func updateLiveActivity() {
        let activity: LiveActivity?
        if let incoming {
            // Over a full-screen app too: a ringing call is worth the interruption, as on iPhone.
            activity = LiveActivity(priority: .urgent, sideWidth: CallMetrics.callerWidth(incoming.caller), showsInFullScreen: true)
        } else if ended != nil {
            activity = LiveActivity(priority: .transient, sideWidth: max(Preferences.compactSideWidth, CallMetrics.timeWidth))
        } else if let call {
            let long = Date().timeIntervalSince(call.since) >= 3600 - 2
            activity = LiveActivity(priority: .active, sideWidth: max(Preferences.compactSideWidth, long ? CallMetrics.longTimeWidth : CallMetrics.timeWidth))
        } else {
            activity = nil
        }
        if activity != liveActivity { liveActivity = activity }
    }

    /// Incoming calls need Accessibility and the user's go-ahead.
    private func updateIncomingMonitor() {
        guard isActive else { return }
        if permission.isGranted && Preferences.callsShowIncoming {
            incomingMonitor.start()
        } else {
            incomingMonitor.stop()
        }
    }

    private func observePermission() {
        withObservationTracking {
            _ = permission.isGranted
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.updateIncomingMonitor()
                self.observePermission()
            }
        }
    }

    #if DEBUG
    /// Fakes calls (debug commands `call:incoming:<name>`, `call:active:<bundle id>`, `call:end`).
    func showDebugCall(_ command: String) {
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "incoming":
            applyIncoming(IncomingCall(caller: parts.count > 1 ? parts[1] : "Jane Appleseed", detail: "FaceTime Audio", appBundleID: CallApps.faceTime))
        case "active":
            applyIncoming(nil)
            let bundleID = parts.count > 1 ? parts[1] : CallApps.faceTime
            endTask?.cancel()
            endTask = nil
            withAnimation(Motion.content) {
                call = OngoingCall(appBundleID: bundleID, appName: CallApps.name(for: bundleID), since: Date().addingTimeInterval(-75))
            }
            updateLiveActivity()
        case "end":
            applyIncoming(nil)
            endCall()
        default: break
        }
    }
    #endif

    // MARK: NotchModule views

    func compactLeading() -> AnyView { AnyView(CallCompactLeading(module: self)) }
    func compactTrailing() -> AnyView { AnyView(CallCompactTrailing(module: self)) }
    func compactMinimal() -> AnyView { AnyView(CallGlyph(module: self)) }
    func expandedView() -> AnyView { AnyView(CallsExpandedView(module: self)) }
    func settingsView() -> AnyView? { AnyView(CallsSettingsView(module: self)) }
}

enum CallMetrics {
    /// "12:04" beside the notch.
    static let timeWidth: CGFloat = 50
    /// "1:02:05".
    static let longTimeWidth: CGFloat = 62

    /// Slot width for a ringing call: the caller's name on the right (the phone on the left gets
    /// the same, so the notch stays centered), capped so a long name shrinks instead.
    static func callerWidth(_ caller: String) -> CGFloat {
        min(max(CGFloat(caller.count) * 7.5 + HUDMetrics.inset + HUDMetrics.notchGap, 56), Metrics.maxCompactSideWidth)
    }
}
