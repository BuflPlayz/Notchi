import AppKit
import os

/// Builds and wires the app's long-lived objects. New modules are registered here.
@MainActor
final class AppEnvironment {
    let registry = ModuleRegistry()
    private let screenTracker = ScreenTracker()
    private let fullScreenMonitor = FullScreenMonitor()
    private var preferencesObserver: NSObjectProtocol?
    private var model: NotchViewModel?
    private var windowController: NotchWindowController?

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        // Order breaks priority ties: a running Clock timer takes the compact slots over playing music.
        registry.register(ClockModule(provider: MobileTimerClockProvider()))
        registry.register(MediaModule(provider: NowPlayingService(), audioMonitor: AudioLevelMonitor()))
        // Files dragged onto the notch.
        registry.register(ShelfModule())
        // System toasts are transient (highest priority) whatever the order.
        registry.register(SystemModule())
    }

    func start() {
        guard let screen = ScreenTracker.mainDisplay else { return }

        let model = NotchViewModel(
            geometry: .make(for: screen, forceIsland: Preferences.forceIsland),
            registry: registry
        )
        windowController = NotchWindowController(model: model)
        self.model = model

        // Re-anchor on display changes: a notch on the built-in display, an island on an external main display.
        screenTracker.onChange = { [weak self, weak model] screen in
            model?.updateGeometry(.make(for: screen, forceIsland: Preferences.forceIsland))
            self?.fullScreenMonitor.displayID = screen.displayID
        }
        screenTracker.start()

        // Full-screen apps hide the notch, if the user wants that.
        fullScreenMonitor.onChange = { [weak self] _ in self?.updateSuppression() }
        fullScreenMonitor.start()
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSuppression() }
        }
        registry.startAll()
        #if DEBUG
        installDebugCommands()
        #endif
    }

    #if DEBUG
    /// Drive the notch from a terminal without touching the mouse, for testing and screen recordings:
    /// `swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("dev.notchi.debug"), object: "expand", userInfo: nil, deliverImmediately: true)'`
    /// Commands: `expand`, `collapse`, `show:<module id>` (open a module's page), `settings`,
    /// `swap:<module id>` (click that module's bubble beside the notch),
    /// `settings:<tab>` (general, modules, clock, media, system, about), `closeSettings`, `hud:volume:0.6` / `hud:brightness:0.3` / `hud:mute`, `audioTap` (runs the visualizer's audio tap for 6 s and logs
    /// the result under subsystem `dev.notchi.Notchi`, category `AudioTap`).
    private func installDebugCommands() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("dev.notchi.debug"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let command = notification.object as? String
            MainActor.assumeIsolated {
                guard let model = self?.model else { return }
                switch command {
                case "expand": model.expandNow()
                case "collapse": model.collapse()
                case "audioTap": self?.runAudioTapCheck()
                case "settings": NotificationCenter.default.post(name: .notchiOpenSettings, object: nil)
                case let command? where command.hasPrefix("settings:"):
                    UserDefaults.standard.set(String(command.dropFirst("settings:".count)), forKey: SettingsView.selectedTabKey)
                    NotificationCenter.default.post(name: .notchiOpenSettings, object: nil)
                case let command? where command.hasPrefix("hud:"):
                    (self?.registry.module(withID: "system") as? SystemModule)?.showDebugHUD(String(command.dropFirst("hud:".count)))
                case let command? where command.hasPrefix("swap:"):
                    model.bringToFront(String(command.dropFirst("swap:".count)))
                case "closeSettings":
                    NSApp.windows.filter { !($0 is NotchPanel) && $0.isVisible }.forEach { $0.close() }
                case let command? where command.hasPrefix("show:"):
                    model.expandNow()  // opening selects the foreground module…
                    model.selectedModuleID = String(command.dropFirst("show:".count))  // …so pick ours after
                default: break
                }
            }
        }
    }

    private func runAudioTapCheck() {
        let logger = Logger(subsystem: "dev.notchi.Notchi", category: "AudioTap")
        let monitor = AudioLevelMonitor()
        monitor.start()
        logger.notice("Audio tap check: running=\(monitor.isRunning, privacy: .public)")
        Task {
            var peak = 0.0
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(100))
                peak = max(peak, monitor.levels.max() ?? 0)
            }
            logger.notice("Audio tap check: peak level \(peak, privacy: .public)")
            monitor.stop()
        }
    }
    #endif

    private func updateSuppression() {
        model?.setSuppressed(fullScreenMonitor.isFullScreen && Preferences.hideInFullScreen)
    }

    func stop() {
        fullScreenMonitor.stop()
        screenTracker.stop()
        registry.stopAll()
    }
}
