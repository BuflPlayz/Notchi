import AppKit
import CoreMediaIO

/// Which microphone users are calls. Everything else that records (Voice Memos, QuickTime) is a
/// recording, shown by `RecordingModule`.
enum CallApps {
    /// Calling apps. Add new ones here. Helpers and XPC services are matched to their app first.
    static let apps: Set<String> = [
        "com.apple.FaceTime",
        "com.apple.mobilephone",
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.cisco.webexmeetingsapp",
        "Cisco-Systems.Spark",
        "com.skype.skype",
        "net.whatsapp.WhatsApp",
        "desktop.WhatsApp",
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
        "org.whispersystems.signal-desktop",
        "com.google.meet",
        "com.ringcentral.glip",
        "com.logmein.GoToMeeting",
    ]

    /// Browsers, for calls on the web (Meet, Teams, Zoom in a tab).
    static let browsers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    /// System daemons that carry FaceTime and iPhone (Continuity) calls.
    static let callDaemons: Set<String> = ["avconferenced", "callservicesd"]

    static let faceTime = "com.apple.FaceTime"
    static let phone = "com.apple.mobilephone"

    static func isCall(_ use: MicrophoneUse, includeBrowsers: Bool) -> Bool {
        if isCallDaemon(use) { return true }
        guard let bundleID = use.bundleID else { return false }
        return apps.contains(bundleID) || (includeBrowsers && browsers.contains(bundleID))
    }

    private static func isCallDaemon(_ use: MicrophoneUse) -> Bool {
        callDaemons.contains(use.processName) || use.bundleID.map { id in callDaemons.contains(where: id.hasSuffix) } == true
    }

    /// Browsers can record for things other than calls, so they're neither calls nor recordings
    /// when browser calls are off.
    static func isRecording(_ use: MicrophoneUse) -> Bool {
        guard !isCall(use, includeBrowsers: true) else { return false }
        // Only apps: dictation, Siri and other agents record now and then without being "a recording".
        return NSRunningApplication(processIdentifier: use.pid)?.activationPolicy == .regular
    }

    /// The app to show for a call: a daemon's call belongs to FaceTime when it's open, otherwise to Phone.
    static func appBundleID(for use: MicrophoneUse) -> String? {
        guard isCallDaemon(use) else { return use.bundleID }
        let faceTimeOpen = !NSRunningApplication.runningApplications(withBundleIdentifier: faceTime).isEmpty
        return faceTimeOpen ? faceTime : phone
    }

    /// "FaceTime", "Zoom".
    static func name(for bundleID: String?) -> String {
        guard let bundleID else { return "Call" }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, let name = app.localizedName {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return "Call" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Brings the app to the front, or opens it.
    static func show(_ bundleID: String?) {
        guard let bundleID else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// Whether any camera is on, from CoreMediaIO (no permission needed). Read while a call is on, so a
/// video call shows the video glyph.
enum Camera {
    static func isInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }
        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            var value: UInt32 = 0
            var valueSize: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &valueSize, &value) == noErr && value != 0
        }
    }
}
