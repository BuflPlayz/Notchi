/// A source of now-playing information and a way to control it.
///
/// Implementations: `MediaRemoteAdapterProvider` (every app, via the system Now Playing service),
/// `AppleScriptNowPlayingProvider` (Music and Spotify only), `NowPlayingService` (picks between
/// them), and `MockNowPlayingProvider` (previews and tests).
@MainActor
protocol NowPlayingProvider: AnyObject {
    /// Where the information comes from, shown in Settings.
    var sourceName: String { get }

    /// Called on the main actor with every change; `nil` means nothing is playing.
    var onUpdate: ((NowPlayingInfo?) -> Void)? { get set }

    func start()
    func stop()
    func send(_ command: MediaCommand)
}
