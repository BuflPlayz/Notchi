import AppKit

/// Which display the notch lives on (Settings › General).
enum NotchDisplay: String, CaseIterable, Identifiable {
    /// The display with the menu bar, "main display" in System Settings.
    case main
    /// The MacBook's own screen, with the camera notch, even when an external display is main.
    case builtIn

    var id: Self { self }

    var title: String {
        switch self {
        case .main: "Main display"
        case .builtIn: "Built-in display"
        }
    }
}

/// Follows the display the notch belongs on (the user's pick) and reports when it or its metrics
/// change.
@MainActor
final class ScreenTracker {
    /// Called with the notch's display on start, after every display reconfiguration, and when the
    /// user picks another display.
    var onChange: ((NSScreen) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var currentDisplayID: CGDirectDisplayID?

    /// `screens[0]` is always the display with the menu bar, i.e. "main display" in System Settings.
    /// (`NSScreen.main` is different: it's whichever screen has the key window.)
    static var mainDisplay: NSScreen? { NSScreen.screens.first }

    /// The MacBook's own screen, if it's on (not with the lid closed, or on a desktop Mac).
    static var builtInDisplay: NSScreen? {
        NSScreen.screens.first { $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false }
    }

    /// The display the notch goes on: the user's pick, or the main display when that one isn't there.
    static var notchDisplay: NSScreen? {
        switch Preferences.notchDisplay {
        case .main: mainDisplay
        case .builtIn: builtInDisplay ?? mainDisplay
        }
    }

    func start() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit() }
        })
        // Any setting changing posts this; only a different display is worth re-anchoring for.
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Self.notchDisplay?.displayID != self.currentDisplayID else { return }
                self.emit()
            }
        })
        emit()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func emit() {
        guard let screen = Self.notchDisplay else { return }
        currentDisplayID = screen.displayID
        onChange?(screen)
    }
}
