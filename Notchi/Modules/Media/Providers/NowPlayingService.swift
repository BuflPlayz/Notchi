import Foundation

/// Picks the now-playing source and switches automatically if the first choice stops working.
///
/// - Primary: the MediaRemote adapter (every app, including browsers, no permissions).
/// - Fallback: Music and Spotify over AppleScript.
///
/// The adapter's own `test` command can briefly publish a fake track, so it's never run. Instead,
/// Music and Spotify already broadcast public "player changed" notifications. If one of them says
/// it's playing and the adapter reports nothing within a few seconds, Apple has closed the
/// loophole, and the service switches to the fallback for the rest of the session.
@MainActor
final class NowPlayingService: NowPlayingProvider {
    var onUpdate: ((NowPlayingInfo?) -> Void)?
    var sourceName: String { active.sourceName }

    private var active: NowPlayingProvider
    private(set) var isUsingAdapter: Bool
    private var lastPlayingReport: Date?
    private var watchdog: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        if let location = MediaRemoteAdapterProvider.Location.bundled {
            active = MediaRemoteAdapterProvider(location: location)
            isUsingAdapter = true
        } else {
            active = AppleScriptNowPlayingProvider()
            isUsingAdapter = false
        }
    }

    func start() {
        attach(active)
        active.start()
        if isUsingAdapter { watchPlayers() }
    }

    func stop() {
        watchdog?.cancel()
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll()
        active.stop()
    }

    func send(_ command: MediaCommand) {
        active.send(command)
    }

    private func attach(_ provider: NowPlayingProvider) {
        provider.onUpdate = { [weak self] info in
            if info?.isPlaying == true { self?.lastPlayingReport = Date() }
            self?.onUpdate?(info)
        }
    }

    // MARK: Adapter health check

    private func watchPlayers() {
        for player in AppleScriptNowPlayingProvider.Player.allCases {
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: player.notification, object: nil, queue: .main
            ) { [weak self] notification in
                let isPlaying = AppleScriptNowPlayingProvider.PlayerEvent(notification.userInfo).state == "Playing"
                MainActor.assumeIsolated { self?.playerReported(isPlaying: isPlaying) }
            }
            observers.append(observer)
        }
    }

    private func playerReported(isPlaying: Bool) {
        guard isPlaying, isUsingAdapter, watchdog == nil else { return }
        let reportedAt = Date()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled else { return }
            self.watchdog = nil
            let adapterSawIt = self.lastPlayingReport.map { $0 > reportedAt.addingTimeInterval(-10) } ?? false
            if !adapterSawIt { self.switchToFallback() }
        }
    }

    private func switchToFallback() {
        active.stop()
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll()
        isUsingAdapter = false
        active = AppleScriptNowPlayingProvider()
        attach(active)
        active.start()
    }
}
