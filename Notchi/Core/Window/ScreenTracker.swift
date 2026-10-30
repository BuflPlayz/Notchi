import AppKit

/// Follows the main display (the one with the menu bar) and reports when it or its metrics change.
@MainActor
final class ScreenTracker {
    /// Called with the current main display on start and after every display reconfiguration.
    var onChange: ((NSScreen) -> Void)?
    private var observer: NSObjectProtocol?

    /// `screens[0]` is always the display with the menu bar, i.e. "main display" in System Settings.
    /// (`NSScreen.main` is different: it's whichever screen has the key window.)
    static var mainDisplay: NSScreen? { NSScreen.screens.first }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit() }
        }
        emit()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func emit() {
        guard let screen = Self.mainDisplay else { return }
        onChange?(screen)
    }
}
