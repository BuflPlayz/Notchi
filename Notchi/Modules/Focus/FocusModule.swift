import AppKit
import SwiftUI

/// Focus (Do Not Disturb, Sleep, Work…) in the notch.
///
/// Turning a Focus on or off is announced in the notch for a few seconds: the Focus's symbol and
/// name, and "On" or "Off". Only into a closed notch with nothing else in it (`canAnnounce`): it
/// never takes over music or a timer, or a notch the user has open. Optionally (Settings › Focus, off by default) an
/// active Focus then stays as a quiet (`ambient`) live activity: in the notch when nothing else is
/// running, or as a bubble beside it.
///
/// Reading Focus needs Accessibility (see `FocusMonitor`), the same permission the volume HUD uses.
@MainActor
@Observable
final class FocusModule: NotchModule {
    let id = "focus"
    let title = "Focus"
    let symbol = "moon.fill"

    private(set) var state = FocusState.inactive
    private(set) var liveActivity: LiveActivity?
    /// True for a few seconds after a Focus turns on or off, while compact mode says so.
    private(set) var isAnnouncing = false
    /// The Focus being announced. Turning off reports no name, so this keeps the one that was on.
    private(set) var announcedName: String?

    let permission = AccessibilityPermission.shared
    /// Whether the notch is free for an announcement right now. Set by the app, which knows the notch.
    @ObservationIgnored var canAnnounce: @MainActor () -> Bool = { true }

    @ObservationIgnored private let monitor = FocusMonitor()
    @ObservationIgnored private let announcement: Duration
    @ObservationIgnored private var announceTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesObserver: NSObjectProtocol?
    /// The first reading is the state at launch, not a change to announce.
    @ObservationIgnored private var hasReading = false
    @ObservationIgnored private var isActive = false

    init(announcement: Duration = .seconds(3)) {
        self.announcement = announcement
    }

    var style: FocusStyle { FocusStyle(name: isAnnouncing ? announcedName : state.name) }

    func start() {
        guard !isActive else { return }
        isActive = true
        monitor.onChange = { [weak self] state in self?.apply(state, announce: self?.hasReading == true) }
        observePermission()
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMonitor()
                self?.updateLiveActivity()
            }
        }
        updateMonitor()
    }

    func stop() {
        isActive = false
        monitor.stop()
        hasReading = false
        announceTask?.cancel()
        isAnnouncing = false
        state = .inactive
        liveActivity = nil
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
        preferencesObserver = nil
    }

    func requestAccessibility() {
        permission.request()
    }

    /// A new reading. A change after launch is announced for a moment (if the user wants that),
    /// then an active Focus settles into a quiet live activity.
    func apply(_ newState: FocusState, announce: Bool) {
        guard newState != state else { return }
        let toggled = newState.isActive != state.isActive
        let previousName = state.name
        withAnimation(Motion.content) { state = newState }
        if announce && toggled && Preferences.focusAlerts && canAnnounce() {
            announcedName = newState.isActive ? newState.name : previousName
            isAnnouncing = true
            announceTask?.cancel()
            let duration = announcement
            announceTask = Task { [weak self] in
                try? await Task.sleep(for: duration)
                guard let self, !Task.isCancelled else { return }
                self.isAnnouncing = false
                self.updateLiveActivity()
            }
        }
        updateLiveActivity()
    }

    #if DEBUG
    /// Pretends a Focus turned on or off (debug commands `focus:Work`, `focus:off`).
    func showDebugFocus(_ name: String) {
        apply(name == "off" ? .inactive : FocusState(isActive: true, name: name), announce: true)
    }
    #endif

    // MARK: NotchModule views

    func compactLeading() -> AnyView { AnyView(FocusCompactLeading(module: self)) }
    func compactTrailing() -> AnyView { AnyView(FocusCompactTrailing(module: self)) }
    func compactMinimal() -> AnyView { AnyView(FocusGlyph(module: self)) }
    /// Focus only announces itself; it has no page in the panel (Settings › Focus has its switches).
    var showsInPanel: Bool { false }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
    func settingsView() -> AnyView? { AnyView(FocusSettingsView(module: self)) }

    // MARK: Private

    private func updateLiveActivity() {
        let activity: LiveActivity?
        if isAnnouncing {
            activity = LiveActivity(priority: .transient, sideWidth: max(Preferences.compactSideWidth, FocusMetrics.announceWidth(forName: announcedName)))
        } else if state.isActive && Preferences.focusActivity {
            activity = LiveActivity(priority: .ambient, sideWidth: max(Preferences.compactSideWidth, FocusMetrics.width(forLabel: style.label)))
        } else {
            activity = nil
        }
        if activity != liveActivity { liveActivity = activity }
    }

    /// Reads Focus only when there's a use for it and permission to.
    private func updateMonitor() {
        guard isActive else { return }
        if permission.isGranted && (Preferences.focusAlerts || Preferences.focusActivity) {
            if !hasReading {
                monitor.start()      // reads the current state synchronously: the baseline…
                hasReading = true    // …so later readings are changes
            }
        } else {
            monitor.stop()
            hasReading = false
            apply(.inactive, announce: false)
        }
    }

    private func observePermission() {
        withObservationTracking {
            _ = permission.isGranted
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.updateMonitor()
                self.observePermission()
            }
        }
    }
}

/// How a Focus looks: the symbol and color macOS uses for the built-in ones, by name. Custom
/// Focuses get the moon.
struct FocusStyle: Equatable {
    let symbol: String
    let color: Color
    /// Short enough for a compact slot.
    let label: String

    init(name: String?) {
        let key = name?.lowercased() ?? ""
        let known: [(match: String, symbol: String, color: Color)] = [
            ("sleep", "bed.double.fill", .cyan),
            ("work", "briefcase.fill", .teal),
            ("personal", "person.fill", .purple),
            ("driving", "car.fill", .blue),
            ("fitness", "figure.run", .green),
            ("gaming", "gamecontroller.fill", .blue),
            ("mindfulness", "figure.mind.and.body", .mint),
            ("reading", "book.fill", .orange),
            ("reduce interruptions", "sparkles", .indigo),
        ]
        let style = known.first { key.contains($0.match) }
        symbol = style?.symbol ?? "moon.fill"
        color = style?.color ?? .indigo
        // "Do Not Disturb" doesn't fit beside the notch; the moon already says it.
        label = key.isEmpty || key == "do not disturb" ? "On" : name!
    }
}

enum FocusMetrics {
    /// Narrowest slot: room for "On" or "Off" and the HUD-style insets.
    static let minimumWidth: CGFloat = 50
    /// Symbol plus the gap before the name.
    static let symbolWidth: CGFloat = 24

    /// Slot width for a Focus's name beside the notch: text plus the HUD-style insets, capped so a
    /// long custom name shrinks instead of widening the notch.
    static func width(forLabel label: String) -> CGFloat {
        min(max(textWidth(label) + HUDMetrics.inset + HUDMetrics.notchGap, minimumWidth), 96)
    }

    /// Slot width while announcing: the symbol and the Focus's full name on the left, so the right
    /// side ("On"/"Off") gets the same width and the notch stays centered.
    static func announceWidth(forName name: String?) -> CGFloat {
        min(symbolWidth + textWidth(name ?? "Focus") + HUDMetrics.inset + HUDMetrics.notchGap, Metrics.maxCompactSideWidth)
    }

    /// Roughly how wide a label is at the compact font (13 pt semibold).
    private static func textWidth(_ text: String) -> CGFloat {
        CGFloat(text.count) * 7.5
    }
}
