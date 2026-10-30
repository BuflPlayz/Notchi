import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Created up front so the Settings scene can reach the module registry.
    let environment = AppEnvironment()
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; don't put a panel on screen for them.
        guard !AppEnvironment.isRunningTests else { return }

        Preferences.registerDefaults()
        environment.start()
        handleTerminationSignal()
    }

    /// `kill`, Activity Monitor and logout send SIGTERM, which skips `applicationWillTerminate`.
    /// Catch it so helper processes (the media stream) and the audio tap are torn down too.
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.environment.stop()
                exit(0)
            }
        }
        source.resume()
        terminationSignal = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
    }
}
