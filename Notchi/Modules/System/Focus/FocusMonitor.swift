import AppKit
import ApplicationServices

/// Whether a Focus (Do Not Disturb, Work, Sleep…) is on.
struct FocusState: Equatable, Sendable {
    var isActive: Bool
    /// The Focus's name when Control Center exposes it, such as "Do Not Disturb".
    var name: String?

    static let inactive = FocusState(isActive: false, name: nil)
}

/// Reads Focus from Control Center's menu bar indicator through Accessibility.
///
/// macOS offers no entitlement-free way to read Focus. `INFocusStatusCenter` needs a provisioned
/// entitlement, and the Focus database is privacy-protected. Control Center shows a Focus item in
/// the menu bar while one is active (System Settings › Control Center › Focus › "Show When
/// Active", the default). This monitor looks for that item and watches Control Center for changes.
/// It reuses the Accessibility permission the HUD already needs, and reports "off" without it.
@MainActor
final class FocusMonitor {
    var onChange: ((FocusState) -> Void)?
    private(set) var state = FocusState.inactive

    private var observer: AXObserver?
    private var application: AXUIElement?
    private var refreshTask: Task<Void, Never>?

    private static let controlCenter = "com.apple.controlcenter"

    func start() {
        guard observer == nil, AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.controlCenter).first?.processIdentifier
        else { return }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let monitor = Unmanaged<FocusMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.scheduleRefresh() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }

        let element = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXCreatedNotification, kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                             kAXValueChangedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(created, element, notification as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        application = element
        refresh()
    }

    func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        application = nil
        refreshTask?.cancel()
    }

    /// Control Center emits bursts of notifications while its menu bar relayouts; read once it settles.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        let newState = application.map(Self.readFocus) ?? .inactive
        guard newState != state else { return }
        state = newState
        onChange?(newState)
    }

    private static func readFocus(from application: AXUIElement) -> FocusState {
        guard let menuBar: AXUIElement = attribute(application, "AXExtrasMenuBar"),
              let items: [AXUIElement] = attribute(menuBar, kAXChildrenAttribute)
        else { return .inactive }

        for item in items {
            let identifier: String = attribute(item, "AXIdentifier") ?? ""
            guard identifier.localizedCaseInsensitiveContains("focus") else { continue }
            let description: String? = attribute(item, kAXDescriptionAttribute) ?? attribute(item, kAXTitleAttribute)
            return FocusState(isActive: true, name: focusName(fromDescription: description))
        }
        return .inactive
    }

    /// Control Center describes the item like "Focus, Do Not Disturb"; keep the Focus's own name.
    nonisolated static func focusName(fromDescription description: String?) -> String? {
        guard let description, !description.isEmpty else { return nil }
        let parts = description.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let name = parts.count > 1 ? parts.last! : parts[0]
        return name.caseInsensitiveCompare("Focus") == .orderedSame ? nil : name
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
