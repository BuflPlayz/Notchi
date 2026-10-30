import AppKit

/// Fallback now playing for Music and Spotify, used only if the MediaRemote adapter is blocked.
///
/// Track changes come from each player's public distributed notification, which is event-driven
/// and needs no permission. Controls, Music's playback position, and artwork use AppleScript. The
/// first such call shows the system "Notchi wants to control Music/Spotify" prompt. Browser media
/// isn't available this way.
@MainActor
final class AppleScriptNowPlayingProvider: NowPlayingProvider {
    enum Player: String, CaseIterable, Sendable {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var notification: Notification.Name {
            switch self {
            case .music: Notification.Name("com.apple.Music.playerInfo")
            case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
            }
        }

        var appName: String {
            switch self {
            case .music: "Music"
            case .spotify: "Spotify"
            }
        }
    }

    /// The parts of a player notification we use, copied out so they can cross actors.
    struct PlayerEvent: Sendable {
        var state: String?
        var title: String?
        var artist: String?
        var album: String?
        /// Track length in milliseconds (Music: "Total Time", Spotify: "Duration").
        var durationMillis: Double?
        /// Spotify reports the position in seconds; Music doesn't include it.
        var position: Double?

        init(_ userInfo: [AnyHashable: Any]?) {
            state = userInfo?["Player State"] as? String
            title = userInfo?["Name"] as? String
            artist = userInfo?["Artist"] as? String
            album = userInfo?["Album"] as? String
            durationMillis = (userInfo?["Total Time"] as? NSNumber ?? userInfo?["Duration"] as? NSNumber)?.doubleValue
            position = (userInfo?["Playback Position"] as? NSNumber)?.doubleValue
        }
    }

    var onUpdate: ((NowPlayingInfo?) -> Void)?
    let sourceName = "Music and Spotify (fallback)"

    private var current: (player: Player, info: NowPlayingInfo)?
    private var observers: [NSObjectProtocol] = []
    private let scripts = AppleScriptRunner()

    func start() {
        guard observers.isEmpty else { return }
        for player in Player.allCases {
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: player.notification, object: nil, queue: .main
            ) { [weak self] notification in
                let event = PlayerEvent(notification.userInfo)
                MainActor.assumeIsolated { self?.handle(event, from: player) }
            }
            observers.append(observer)
        }
    }

    func stop() {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll()
    }

    func send(_ command: MediaCommand) {
        guard let player = current?.player else { return }
        let verb = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        case .seek(let position): "set player position to \(position)"
        }
        scripts.run("tell application \"\(player.appName)\" to \(verb)")
    }

    // MARK: Events

    private func handle(_ event: PlayerEvent, from player: Player) {
        guard event.state != "Stopped", let title = event.title, !title.isEmpty else {
            if current?.player == player {
                current = nil
                onUpdate?(nil)
            }
            return
        }

        var info = NowPlayingInfo(
            title: title,
            artist: event.artist.flatMap { $0.isEmpty ? nil : $0 },
            album: event.album.flatMap { $0.isEmpty ? nil : $0 },
            duration: event.durationMillis.map { $0 / 1000 },
            elapsed: event.position ?? 0,
            timestamp: Date(),
            playbackRate: 1,
            isPlaying: event.state == "Playing",
            artworkData: nil,
            sourceBundleIdentifier: player.rawValue
        )
        let isSameTrack = current?.player == player && info.isSameTrack(as: current?.info)
        if isSameTrack { info.artworkData = current?.info.artworkData }
        publish(info, from: player)

        if player == .music { refreshMusicPosition() }
        if !isSameTrack { loadArtwork(for: player, title: title) }
    }

    private func publish(_ info: NowPlayingInfo, from player: Player) {
        current = (player, info)
        onUpdate?(info)
    }

    /// Music's notification has no position; ask for it.
    private func refreshMusicPosition() {
        Task { [weak self] in
            guard let position = await self?.scripts.double("tell application \"Music\" to player position"),
                  let self, var info = self.current?.info, self.current?.player == .music
            else { return }
            info.elapsed = position
            info.timestamp = Date()
            self.publish(info, from: .music)
        }
    }

    private func loadArtwork(for player: Player, title: String) {
        Task { [weak self] in
            guard let scripts = self?.scripts else { return }
            let data: Data? = switch player {
            case .music:
                await scripts.data("tell application \"Music\" to get raw data of artwork 1 of current track")
            case .spotify:
                await Self.download(await scripts.string("tell application \"Spotify\" to get artwork url of current track"))
            }
            // Ignore artwork that arrives after the track already changed.
            guard let data, let self, var info = self.current?.info, self.current?.player == player, info.title == title
            else { return }
            info.artworkData = data
            self.publish(info, from: player)
        }
    }

    private nonisolated static func download(_ urlString: String?) async -> Data? {
        guard let urlString, let url = URL(string: urlString), url.scheme == "https" else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }
}

/// Runs AppleScript off the main thread. NSAppleScript isn't thread-safe, so every script runs on
/// one serial queue, and a pending permission prompt never blocks the UI.
final class AppleScriptRunner: Sendable {
    private let queue = DispatchQueue(label: "dev.notchi.applescript", qos: .userInitiated)

    func run(_ source: String) {
        queue.async { _ = Self.execute(source) }
    }

    func string(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Self.execute(source)?.stringValue) }
        }
    }

    func double(_ source: String) async -> Double? {
        await string(source).flatMap(Double.init)
    }

    func data(_ source: String) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Self.execute(source)?.data) }
        }
    }

    private static func execute(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
