import AppKit
import ApplicationServices

/// Accessibility ("control your computer") permission: needed to intercept the volume and
/// brightness keys and to read Control Center's Focus indicator.
///
/// Requested lazily, only when the user enables a feature that needs it, never at launch. macOS
/// broadcasts `com.apple.accessibility.api` when any app's trust changes, so grants are noticed
/// without polling.
@MainActor
@Observable
final class AccessibilityPermission {
    static let shared = AccessibilityPermission()

    private(set) var isGranted = AXIsProcessTrusted()

    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The trust database updates just after the broadcast.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.isGranted = AXIsProcessTrusted()
            }
        }
    }

    /// Shows the system prompt that leads to System Settings › Privacy & Security › Accessibility.
    func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isGranted = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the Accessibility list in System Settings directly.
    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
