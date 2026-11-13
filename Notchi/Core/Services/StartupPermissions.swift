import AppKit
import OSLog

/// Asks at launch for the permissions the enabled features need, so they work from the start
/// instead of waiting for the first song or a trip to Settings.
///
/// - System Audio Recording, for the visualizer (Now Playing on, "Visualizer follows the music" on).
/// - Accessibility, for the volume and brightness keys, Focus, incoming calls and stopping a
///   Screenshot-toolbar recording.
///
/// Only what's missing is asked for, one prompt at a time. macOS asks about each permission once:
/// after a "Don't Allow" its prompt stays away, and the Accessibility prompt points to System
/// Settings until the switch is turned on there.
///
/// macOS ties a permission to the app's signing identity. When that changes (moving from ad-hoc
/// builds to signed ones, or between a local build and a release), the old entry stays in System
/// Settings, switched on but ignored, and it blocks a new one, so people had to remove it by hand.
/// So the first launch under a new identity clears Notchi's own entries that aren't working before
/// asking. Working ones are left alone.
@MainActor
enum StartupPermissions {
    private static let logger = Logger(subsystem: "dev.notchi.Notchi", category: "Permissions")

    static func requestMissing(registry: ModuleRegistry) {
        clearStaleEntriesIfIdentityChanged()
        requestAudioCaptureIfNeeded(registry: registry) {
            requestAccessibilityIfNeeded(registry: registry)
        }
    }

    // MARK: Stale entries

    private static func clearStaleEntriesIfIdentityChanged() {
        guard let identity = UpdateInstaller.ownRequirementString, let bundleID = Bundle.main.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Preferences.Key.permissionIdentity) != identity else { return }
        if !AXIsProcessTrusted() {
            resetPermission("Accessibility", for: bundleID)
        }
        if AudioCapturePermission.status == .denied {
            resetPermission("AudioCapture", for: bundleID)
        }
        defaults.set(identity, forKey: Preferences.Key.permissionIdentity)
    }

    /// Clears Notchi's own entry for one permission, like `tccutil reset <service> <bundle id>`.
    private static func resetPermission(_ service: String, for bundleID: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            logger.notice("New signing identity: cleared the old \(service, privacy: .public) entry (\(process.terminationStatus))")
        } catch {
            logger.error("Couldn't clear the old \(service, privacy: .public) entry: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Accessibility

    private static func requestAccessibilityIfNeeded(registry: ModuleRegistry) {
        let needed = (registry.isEnabled("system") && Preferences.replaceSystemHUD)
            || (registry.isEnabled("focus") && (Preferences.focusAlerts || Preferences.focusActivity))
            || (registry.isEnabled("calls") && Preferences.callsShowIncoming)
            || registry.isEnabled("recording")
        let granted = AccessibilityPermission.shared.isGranted
        logger.notice("Accessibility: \(granted ? "granted" : needed ? "asking" : "not needed", privacy: .public)")
        guard needed, !granted else { return }
        AccessibilityPermission.shared.request()
    }

    // MARK: System Audio Recording

    private static func requestAudioCaptureIfNeeded(registry: ModuleRegistry, then next: @escaping @MainActor () -> Void) {
        guard registry.isEnabled("media"), Preferences.realAudioVisualizer else { return next() }
        let status = AudioCapturePermission.status
        logger.notice("System Audio Recording: \(String(describing: status), privacy: .public)")
        guard status == .notDetermined else { return next() }
        AudioCapturePermission.request { granted in
            logger.notice("System Audio Recording answered: \(granted ? "allowed" : "denied", privacy: .public)")
            next()
        }
    }
}

/// The "System Audio Recording Only" permission. macOS has no public call to check or ask for it
/// (it's otherwise asked the first time a process tap runs), so this uses TCC's own functions, the
/// way Apple's audio tap sample apps do. If they're ever missing, it reports `.unknown` and the
/// visualizer asks on first use as before.
enum AudioCapturePermission {
    enum Status: CustomStringConvertible {
        case granted, denied, notDetermined, unknown

        var description: String {
            switch self {
            case .granted: "granted"
            case .denied: "denied"
            case .notDetermined: "not asked yet"
            case .unknown: "unknown"
            }
        }
    }

    nonisolated(unsafe) private static let service = "kTCCServiceAudioCapture" as CFString
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @convention(block) @escaping (Bool) -> Void) -> Void

    nonisolated(unsafe) private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let tcc, let symbol = dlsym(tcc, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    static var status: Status {
        guard let preflight = function("TCCAccessPreflight", as: Preflight.self) else { return .unknown }
        switch preflight(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .notDetermined
        }
    }

    /// Shows the system prompt. `completion` runs on the main actor.
    @MainActor
    static func request(completion: @escaping @MainActor (Bool) -> Void) {
        guard let request = function("TCCAccessRequest", as: Request.self) else { return completion(false) }
        request(service, nil) { granted in
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(granted) } }
        }
    }
}
