import AppKit
import ApplicationServices

/// Whether a Focus (Do Not Disturb, Work, Sleep…) is on.
struct FocusState: Equatable, Sendable {
    var isActive: Bool
    /// The Focus's name when Control Center exposes it, such as "Do Not Disturb".
    var name: String?

    static let inactive = FocusState(isActive: false, name: nil)
}

/// Reads Focus from the menu bar's Focus indicator through Accessibility.
///
/// macOS offers no entitlement-free way to read Focus. `INFocusStatusCenter` needs a provisioned
/// entitlement, and the Focus database is privacy-protected. macOS shows a Focus item in the menu
/// bar while one is active (System Settings › Control Center › Focus › "Show When Active", the
/// default). This monitor looks for that item and watches its process for changes. It reuses the
/// Accessibility permission the HUD already needs, and reports "off" without it.
///
/// The system's menu bar items belong to `MenuBarAgent` since macOS 27 (Control Center's own
/// extras menu bar is empty there), and to Control Center before that.
///
/// Accessibility notifications alone are too slow and unreliable for this (measured on macOS
/// 27.2): "destroyed" arrived 0.73 s after the Focus item had gone, and "created" arrived before
/// the item could be read. So the monitor also checks the menu bar's item count four times a
/// second, a single cheap query, and reads the items fully only when it changes. Every change
/// triggers a short burst of reads, which catches an item that's still being set up.
@MainActor
final class FocusMonitor {
    var onChange: ((FocusState) -> Void)?
    private(set) var state = FocusState.inactive

    private var observer: AXObserver?
    private var application: AXUIElement?
    private var menuBar: AXUIElement?
    private var itemCount = -1
    private var countTimer: Timer?
    private var burstTask: Task<Void, Never>?

    /// How often the item count is checked, and when a change is read again after the first read.
    private static let countInterval: TimeInterval = 0.25
    private static let burstDelays: [Duration] = [.milliseconds(60), .milliseconds(150), .milliseconds(300), .milliseconds(600)]

    /// Processes that may own the system's menu bar items, newest macOS first.
    private static let hosts = ["com.apple.MenuBarAgent", "com.apple.controlcenter"]

    /// The running process whose extras menu bar actually has items.
    static func menuBarHost() -> pid_t? {
        let pids = hosts.compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.processIdentifier }
        return pids.first { pid in
            let items: [AXUIElement]? = extrasMenuBar(of: AXUIElementCreateApplication(pid)).flatMap { attribute($0, kAXChildrenAttribute) }
            return items?.isEmpty == false
        } ?? pids.first
    }

    func start() {
        guard observer == nil, AXIsProcessTrusted(), let pid = Self.menuBarHost() else { return }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, context in
            guard let context else { return }
            let monitor = Unmanaged<FocusMonitor>.fromOpaque(context).takeUnretainedValue()
            #if DEBUG
            let name = notification as String
            MainActor.assumeIsolated { FocusMonitor.trace?("AX \(name)") }
            #endif
            MainActor.assumeIsolated { monitor.refreshBurst() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }

        let element = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Items come and go as children of the extras menu bar; watch it as well as the process.
        let watched = [element] + (Self.extrasMenuBar(of: element).map { [$0] } ?? [])
        for target in watched {
            for notification in [kAXCreatedNotification, kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                                 kAXValueChangedNotification, kAXLayoutChangedNotification] {
                AXObserverAddNotification(created, target, notification as CFString, context)
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        application = element
        menuBar = Self.extrasMenuBar(of: element)
        itemCount = currentItemCount() ?? -1
        let timer = Timer.scheduledTimer(withTimeInterval: Self.countInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkItemCount() }
        }
        timer.tolerance = 0.05
        countTimer = timer
        refresh()
    }

    func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        application = nil
        menuBar = nil
        countTimer?.invalidate()
        countTimer = nil
        burstTask?.cancel()
        burstTask = nil
    }

    /// The Focus item appearing or disappearing changes how many items the menu bar has.
    private func checkItemCount() {
        guard let count = currentItemCount() else {
            // The menu bar's process restarted (or went away): start over with the new one.
            stop()
            start()
            return
        }
        guard count != itemCount else { return }
        itemCount = count
        refreshBurst()
    }

    /// Nil when the menu bar can't be asked anymore.
    private func currentItemCount() -> Int? {
        guard let menuBar else { return nil }
        var count: CFIndex = 0
        let error = AXUIElementGetAttributeValueCount(menuBar, kAXChildrenAttribute as CFString, &count)
        return error == .success ? count : (error == .invalidUIElement ? nil : itemCount)
    }

    /// Reads now, then a few more times over the next moments: a new item can take a little while
    /// to become readable after it appears.
    private func refreshBurst() {
        refresh()
        burstTask?.cancel()
        burstTask = Task { [weak self] in
            var elapsed = Duration.zero
            for delay in Self.burstDelays {
                try? await Task.sleep(for: delay - elapsed)
                guard !Task.isCancelled else { return }
                elapsed = delay
                self?.refresh()
            }
        }
    }

    func refresh() {
        let newState = application.map(Self.readFocus) ?? .inactive
        #if DEBUG
        Self.trace?("refresh → \(newState.isActive ? "on \(newState.name ?? "")" : "off")")
        #endif
        guard newState != state else { return }
        state = newState
        onChange?(newState)
    }

    private static func readFocus(from application: AXUIElement) -> FocusState {
        guard let menuBar = extrasMenuBar(of: application),
              let items: [AXUIElement] = attribute(menuBar, kAXChildrenAttribute)
        else { return .inactive }

        // On macOS 27 each item is wrapped in a hosting group; earlier, the items are direct children.
        let candidates = items.flatMap { item in [item] + ((attribute(item, kAXChildrenAttribute) as [AXUIElement]?) ?? []) }
        for item in candidates {
            let identifier: String = attribute(item, "AXIdentifier") ?? ""
            guard identifier.localizedCaseInsensitiveContains("focus") else { continue }
            let description: String? = attribute(item, kAXDescriptionAttribute) ?? attribute(item, kAXTitleAttribute)
            return FocusState(isActive: true, name: focusName(fromDescription: description))
        }
        return .inactive
    }

    #if DEBUG
    /// Receives trace lines while the `focusTrace` debug command runs.
    static var trace: ((String) -> Void)?

    /// Reads the Focus item right now, for the trace's poll.
    static func debugReadNow() -> String {
        guard let pid = menuBarHost() else { return "no host" }
        let state = readFocus(from: AXUIElementCreateApplication(pid))
        return state.isActive ? "on \(state.name ?? "")" : "off"
    }

    /// The menu bar items the monitor can see, as "identifier | description" (debug command `focusDump`).
    static func debugDump() -> String {
        guard let pid = menuBarHost() else { return "No menu bar host running" }
        let host = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "\(pid)"
        let items: [AXUIElement] = extrasMenuBar(of: AXUIElementCreateApplication(pid)).flatMap { attribute($0, kAXChildrenAttribute) } ?? []
        let elements = items.flatMap { [$0] + ((attribute($0, kAXChildrenAttribute) as [AXUIElement]?) ?? []) }
        let lines = elements.compactMap { element -> String? in
            guard let identifier: String = attribute(element, "AXIdentifier") else { return nil }
            return "\(identifier) | \((attribute(element, kAXDescriptionAttribute) as String?) ?? "-")"
        }
        return (["host \(host)"] + lines).joined(separator: "\n")
    }
    #endif

    /// Control Center describes the item like "Focus, Do Not Disturb"; keep the Focus's own name.
    nonisolated static func focusName(fromDescription description: String?) -> String? {
        guard let description, !description.isEmpty else { return nil }
        let parts = description.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let name = parts.count > 1 ? parts.last! : parts[0]
        return name.caseInsensitiveCompare("Focus") == .orderedSame ? nil : name
    }

    private static func extrasMenuBar(of application: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, "AXExtrasMenuBar" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
