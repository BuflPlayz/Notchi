import Foundation

/// What's playing, from whichever provider is active.
///
/// Times follow MediaRemote's model: `elapsed` was true at `timestamp`, and while playing it
/// advances at `playbackRate`. So views compute the live position without anyone polling.
struct NowPlayingInfo: Equatable, Sendable {
    var title: String
    var artist: String?
    var album: String?
    var duration: TimeInterval?
    var elapsed: TimeInterval
    var timestamp: Date
    var playbackRate: Double
    var isPlaying: Bool
    var artworkData: Data?
    /// App that owns the session. For browser media this is the browser, not its helper process.
    var sourceBundleIdentifier: String?

    /// Playback position at `date`, clamped to the track.
    func elapsed(at date: Date) -> TimeInterval {
        var position = elapsed
        if isPlaying {
            // Some players report 0 while playing; treat that as normal speed.
            position += date.timeIntervalSince(timestamp) * (playbackRate > 0 ? playbackRate : 1)
        }
        if let duration, duration > 0 { position = min(position, duration) }
        return max(position, 0)
    }

    /// Same track, ignoring position and play state.
    func isSameTrack(as other: NowPlayingInfo?) -> Bool {
        guard let other else { return false }
        return title == other.title && artist == other.artist && album == other.album
            && sourceBundleIdentifier == other.sourceBundleIdentifier
    }
}

/// Transport commands every provider understands.
enum MediaCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    case seek(to: TimeInterval)
}
