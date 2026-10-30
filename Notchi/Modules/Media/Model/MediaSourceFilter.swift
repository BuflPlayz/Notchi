/// Which apps' media the notch shows.
///
/// By default only music and audio streaming apps count. Browsers (YouTube, Netflix tabs…) and
/// video players are ignored unless "Show media from browsers and video apps" is on in Settings.
enum MediaSourceFilter {
    /// Music and audio streaming apps. Add new ones here.
    static let musicApps: Set<String> = [
        "com.apple.Music",
        "com.apple.podcasts",
        "com.spotify.client",
        "com.tidal.desktop",
        "com.deezer.deezer-desktop",
        "com.amazon.music",
    ]

    static func allows(_ bundleIdentifier: String?, includeAllApps: Bool = Preferences.showAllMediaSources) -> Bool {
        if includeAllApps { return true }
        guard let bundleIdentifier else { return false }
        return musicApps.contains(bundleIdentifier)
    }
}
