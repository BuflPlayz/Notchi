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
        // The default module order (Settings › Modules › Restore Defaults). It also breaks priority
        // ties: a call takes the compact slots over playing music, music over a running Clock
        // timer, and a timer over a recording.
        // System toasts are transient (highest priority) whatever the order.
        registry.register(SystemModule())
        registry.register(CallsModule())
        registry.register(MediaModule(provider: NowPlayingService(), audioMonitor: AudioLevelMonitor()))
        registry.register(ClockModule(provider: MobileTimerClockProvider()))
        // Files dragged onto the notch.
        registry.register(ShelfModule())
        // An active Focus, quiet unless nothing else is running.
        registry.register(FocusModule())
        registry.register(CaptureModule())
        // Coding agents at work, one live activity per running session.
        registry.register(AgentsModule())
    }

    func start() {
        guard let screen = ScreenTracker.mainDisplay else { return }

        let model = NotchViewModel(
            geometry: .make(for: screen, forceIsland: Preferences.forceIsland),
            registry: registry
        )
        windowController = NotchWindowController(model: model)
        self.model = model
        // Focus announces itself only into a closed notch with nothing else in it (a Focus kept in
        // the notch doesn't count).
        (registry.module(withID: "focus") as? FocusModule)?.canAnnounce = { [weak model] in
            guard let model, model.state != .expanded else { return false }
            return !model.registry.activityModules.contains { $0.id != "focus" && $0.liveActivity != nil }
        }

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
    /// `swap:<module id>` (click that module's bubble beside the notch), `focus:<name>` / `focus:off`,
    /// `agent:<claude|codex|gemini>:<working|thinking|plan|waiting|done|failed>` / `agent:clear` (fake sessions),
    /// `hud:charging:0.76` / `hud:low:0.1` (battery toasts), `call:incoming:<name>` / `call:active:<bundle id>` /
    /// `call:end` (fake calls), `rec:screen` / `rec:audio` / `rec:off` (fake recordings), `callDump` (Notification
    /// Center's windows, to see how a call's alert is built, written to `$TMPDIR`), `focusDump` / `focusTrace` (what the Focus
    /// monitor sees, written to `$TMPDIR`),
    /// `settings:<tab>` (general, modules, clock, media, system, about), `closeSettings`, `installUpdate:<version>:<dmg path>` (installs a local DMG through the updater), `hud:volume:0.6` / `hud:brightness:0.3` / `hud:mute`, `audioTap` (runs the visualizer's audio tap for 6 s and logs
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
                case "focusTrace": self?.runFocusTrace()
                case "focusDump":
                    let path = FileManager.default.temporaryDirectory.appending(path: "notchi-focus-dump.txt").path
                    try? FocusMonitor.debugDump().write(toFile: path, atomically: true, encoding: .utf8)
                case let command? where command.hasPrefix("focus:"):
                    (self?.registry.module(withID: "focus") as? FocusModule)?.showDebugFocus(String(command.dropFirst("focus:".count)))
                case let command? where command.hasPrefix("call:"):
                    (self?.registry.module(withID: "calls") as? CallsModule)?.showDebugCall(String(command.dropFirst("call:".count)))
                case let command? where command.hasPrefix("rec:"):
                    (self?.registry.module(withID: "recording") as? CaptureModule)?.showDebugRecording(String(command.dropFirst("rec:".count)))
                case "callDump":
                    let path = FileManager.default.temporaryDirectory.appending(path: "notchi-call-dump.txt").path
                    try? IncomingCallMonitor.debugDump().write(toFile: path, atomically: true, encoding: .utf8)
                case let command? where command.hasPrefix("agent:"):
                    (self?.registry.module(withID: "agents") as? AgentsModule)?.showDebugAgent(String(command.dropFirst("agent:".count)))
                case let command? where command.hasPrefix("swap:"):
                    model.bringToFront(String(command.dropFirst("swap:".count)))
                case let command? where command.hasPrefix("installUpdate:"):
                    // installUpdate:<version>:<path to a DMG>: install it like a release from GitHub.
                    let parts = command.dropFirst("installUpdate:".count).split(separator: ":", maxSplits: 1).map(String.init)
                    if parts.count == 2, let version = AppVersion(parts[0]) {
                        let dmg = URL(fileURLWithPath: parts[1])
                        UpdateChecker.shared.install(.init(version: version, pageURL: dmg, downloadURL: dmg))
                    }
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

    /// For 40 s, records every menu bar AX notification, each read the Focus monitor makes, and (by a
    /// 100 ms poll, only while tracing) when the Focus item really appears, with timestamps, to
    /// `$TMPDIR/notchi-focus-trace.txt`.
    private func runFocusTrace() {
        let trace = TraceFile(path: FileManager.default.temporaryDirectory.appending(path: "notchi-focus-trace.txt").path)
        let log: @MainActor (String) -> Void = { trace.append($0) }
        log("trace started")
        FocusMonitor.trace = log
        var last = FocusMonitor.debugReadNow()
        log("poll \(last)")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = FocusMonitor.debugReadNow()
                if now != last { log("poll \(now)"); last = now }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(40))
            poll.invalidate()
            FocusMonitor.trace = nil
            log("trace ended")
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

#if DEBUG
/// Timestamped lines written to a file as they come, for the `focusTrace` debug command.
@MainActor
private final class TraceFile {
    private let path: String
    private let start = Date()
    private var lines: [String] = []

    init(path: String) { self.path = path }

    func append(_ line: String) {
        lines.append(String(format: "%7.3f ", Date().timeIntervalSince(start)) + line)
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
#endif
