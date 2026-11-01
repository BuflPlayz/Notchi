import AppKit
import ApplicationServices

/// A call ringing on this Mac: FaceTime, or an iPhone call through Continuity.
struct IncomingCall: Equatable, Sendable {
    /// The caller's name or number.
    var caller: String
    /// What the alert says besides the caller, such as "FaceTime Audio".
    var detail: String?
    /// FaceTime or Phone.
    var appBundleID: String

    static let acceptLabels = ["accept", "answer"]
    static let declineLabels = ["decline"]

    /// Reads a Notification Center alert: an incoming call has both an Accept and a Decline button.
    /// `texts` are the alert's labels in reading order, `controls` its buttons' and actions' names.
    init?(texts: [String], controls: [String]) {
        let labels = controls.map { $0.lowercased() }
        guard labels.contains(where: { label in Self.acceptLabels.contains { label.hasPrefix($0) } }),
              labels.contains(where: { label in Self.declineLabels.contains { label.hasPrefix($0) } })
        else { return nil }
        let appNames: Set<String> = ["facetime", "phone", "notification center"]
        let lines = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !appNames.contains($0.lowercased()) && !labels.contains($0.lowercased()) }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        caller = lines.first ?? "Incoming Call"
        detail = lines.dropFirst().first
        appBundleID = texts.contains { $0.localizedCaseInsensitiveContains("FaceTime") } ? CallApps.faceTime : CallApps.phone
    }

    init(caller: String, detail: String?, appBundleID: String) {
        self.caller = caller
        self.detail = detail
        self.appBundleID = appBundleID
    }

    /// An action's name from its accessibility description: custom actions read
    /// "Name:Accept\nTarget:0x0\nSelector:(null)".
    nonisolated static func actionLabel(_ action: String) -> String {
        guard action.hasPrefix("Name:") else { return action }
        return String(action.dropFirst("Name:".count).prefix { $0 != "\n" })
    }
}

/// Finds an incoming call alert in Notification Center through Accessibility, and answers or
/// declines it by pressing the alert's own buttons.
///
/// macOS has no public API for calls, and TelephonyUtilities needs Apple's entitlements. The alert
/// for an incoming FaceTime or iPhone call is a Notification Center notification with Accept and
/// Decline buttons, so the monitor watches Notification Center's windows and reads any that
/// appear. While a call rings it also checks twice a second, to notice when the alert goes
/// (answered, declined or missed); with nothing ringing it only listens.
@MainActor
final class IncomingCallMonitor {
    var onChange: ((IncomingCall?) -> Void)?
    private(set) var call: IncomingCall?

    private var observer: AXObserver?
    private var application: AXUIElement?
    private var accept: (element: AXUIElement, action: String)?
    private var decline: (element: AXUIElement, action: String)?
    private var ringTimer: Timer?
    private var burstTask: Task<Void, Never>?
    private var launchObserver: NSObjectProtocol?

    static let bundleID = "com.apple.notificationcenterui"

    func start() {
        guard observer == nil, AXIsProcessTrusted() else { return }
        if launchObserver == nil {
            // Notification Center restarting gets a new process; follow it.
            launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.bundleID else { return }
                MainActor.assumeIsolated {
                    self?.detach()
                    self?.start()
                }
            }
        }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first?.processIdentifier else { return }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let monitor = Unmanaged<IncomingCallMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refreshBurst() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let element = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXUIElementDestroyedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(created, element, notification as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        application = element
        refresh()
    }

    func stop() {
        detach()
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        launchObserver = nil
        update(nil)
    }

    func answer() { press(accept) }
    func reject() { press(decline) }

    private func press(_ control: (element: AXUIElement, action: String)?) {
        guard let control else { return }
        AXUIElementPerformAction(control.element, control.action as CFString)
        refreshBurst()
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        application = nil
        burstTask?.cancel()
        burstTask = nil
    }

    /// Reads now and over the next moments: a new alert takes a little while to become readable.
    private func refreshBurst() {
        refresh()
        burstTask?.cancel()
        burstTask = Task { [weak self] in
            var elapsed = Duration.zero
            for delay in [Duration.milliseconds(80), .milliseconds(250), .milliseconds(600)] {
                try? await Task.sleep(for: delay - elapsed)
                guard !Task.isCancelled else { return }
                elapsed = delay
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let application else { return update(nil) }
        let windows: [AXUIElement] = Self.attribute(application, kAXWindowsAttribute) ?? []
        for window in windows {
            var texts: [String] = []
            var controls: [(label: String, element: AXUIElement, action: String)] = []
            Self.collect(window, depth: 0, texts: &texts, controls: &controls)
            guard let call = IncomingCall(texts: texts, controls: controls.map(\.label)) else { continue }
            func control(_ labels: [String]) -> (AXUIElement, String)? {
                controls.first { control in labels.contains { control.label.lowercased().hasPrefix($0) } }.map { ($0.element, $0.action) }
            }
            accept = control(IncomingCall.acceptLabels)
            decline = control(IncomingCall.declineLabels)
            return update(call)
        }
        accept = nil
        decline = nil
        update(nil)
    }

    private func update(_ newCall: IncomingCall?) {
        if newCall != nil, ringTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 0.1
            ringTimer = timer
        } else if newCall == nil {
            ringTimer?.invalidate()
            ringTimer = nil
        }
        guard newCall != call else { return }
        call = newCall
        onChange?(newCall)
    }

    /// Gathers an alert's labels and its buttons (or named custom actions).
    private static func collect(
        _ element: AXUIElement, depth: Int,
        texts: inout [String], controls: inout [(label: String, element: AXUIElement, action: String)]
    ) {
        guard depth < 12 else { return }
        let role: String = attribute(element, kAXRoleAttribute) ?? ""
        let title: String? = attribute(element, kAXTitleAttribute)
        let description: String? = attribute(element, kAXDescriptionAttribute)
        if role == kAXStaticTextRole as String, let value: String = attribute(element, kAXValueAttribute) {
            texts.append(value)
        }
        if role == kAXButtonRole as String, let label = [title, description].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
            controls.append((label, element, kAXPressAction as String))
        }
        var names: CFArray?
        if AXUIElementCopyActionNames(element, &names) == .success, let names = names as? [String] {
            for name in names where name.hasPrefix("Name:") {
                controls.append((IncomingCall.actionLabel(name), element, name))
            }
        }
        for child in (attribute(element, kAXChildrenAttribute) as [AXUIElement]?) ?? [] {
            collect(child, depth: depth + 1, texts: &texts, controls: &controls)
        }
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    #if DEBUG
    /// Notification Center's windows as an indented tree of role, labels and actions (debug
    /// command `callDump`), to see how an incoming call's alert is built.
    static func debugDump() -> String {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier else {
            return "Notification Center isn't running"
        }
        var lines: [String] = []
        func dump(_ element: AXUIElement, _ depth: Int) {
            guard depth < 14 else { return }
            var names: CFArray?
            AXUIElementCopyActionNames(element, &names)
            let parts: [String] = [
                attribute(element, kAXRoleAttribute) ?? "?",
                attribute(element, kAXSubroleAttribute) ?? "",
                (attribute(element, "AXIdentifier") as String?).map { "id=\($0)" } ?? "",
                (attribute(element, kAXTitleAttribute) as String?).map { "title=\($0)" } ?? "",
                (attribute(element, kAXDescriptionAttribute) as String?).map { "desc=\($0)" } ?? "",
                (attribute(element, kAXValueAttribute) as String?).map { "value=\($0)" } ?? "",
                "actions=\(((names as? [String]) ?? []).map(IncomingCall.actionLabel))",
            ]
            lines.append(String(repeating: "  ", count: depth) + parts.filter { !$0.isEmpty }.joined(separator: " "))
            for child in (attribute(element, kAXChildrenAttribute) as [AXUIElement]?) ?? [] { dump(child, depth + 1) }
        }
        let windows: [AXUIElement] = attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) ?? []
        windows.forEach { dump($0, 0) }
        return lines.joined(separator: "\n")
    }
    #endif
}
