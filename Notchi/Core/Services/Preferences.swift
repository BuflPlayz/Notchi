import Foundation

/// UserDefaults-backed settings. The Settings window edits the same keys with `@AppStorage`;
/// everything that reads them observes `UserDefaults.didChangeNotification`, so changes apply live.
enum Preferences {
    enum Key {
        static let expandDelay = "expandDelay"
        static let collapseDelay = "collapseDelay"
        static let hapticsEnabled = "hapticsEnabled"
        static let compactSideWidth = "compactSideWidth"
        static let expandedWidth = "expandedWidth"
        static let showAllMediaSources = "showAllMediaSources"
        static let realAudioVisualizer = "realAudioVisualizer"
        static let replaceSystemHUD = "replaceSystemHUD"
        static let batteryAlerts = "batteryAlerts"
        static let focusAlerts = "focusAlerts"
        static let openOnHover = "openOnHover"
        static let islandVisibleWhenIdle = "islandVisibleWhenIdle"
        static let clockShowsPaused = "clockShowsPaused"
        static let hideInFullScreen = "hideInFullScreen"
        /// Debug: draw the Dynamic Island even on a notched display. Launch with `-NotchiForceIsland YES`.
        static let forceIsland = "NotchiForceIsland"
    }

    /// Every key Notchi stores, for "Reset All Settings".
    static let allKeys = [
        Key.expandDelay, Key.collapseDelay, Key.hapticsEnabled, Key.compactSideWidth, Key.expandedWidth,
        Key.showAllMediaSources, Key.realAudioVisualizer, Key.replaceSystemHUD, Key.batteryAlerts,
        Key.focusAlerts, Key.openOnHover, Key.islandVisibleWhenIdle, Key.clockShowsPaused, Key.hideInFullScreen,
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.expandDelay: 0.15,
            Key.collapseDelay: 0.3,
            Key.hapticsEnabled: true,
            Key.compactSideWidth: Double(Metrics.compactSideWidth),
            Key.expandedWidth: Double(Metrics.expandedWidth),
            Key.showAllMediaSources: false,
            Key.realAudioVisualizer: true,
            Key.replaceSystemHUD: true,
            Key.batteryAlerts: true,
            Key.focusAlerts: true,
            Key.openOnHover: true,
            Key.islandVisibleWhenIdle: true,
            Key.clockShowsPaused: true,
            Key.hideInFullScreen: true,
            Key.forceIsland: false,
        ])
    }

    /// Hover dwell before expanding, so passing the cursor over the notch doesn't open it.
    static var expandDelay: Double { value(Key.expandDelay, default: 0.15) }
    /// Grace period after the cursor leaves before collapsing.
    static var collapseDelay: Double { value(Key.collapseDelay, default: 0.3) }
    /// Width of each compact slot beside the notch, in points.
    static var compactSideWidth: CGFloat { CGFloat(value(Key.compactSideWidth, default: Double(Metrics.compactSideWidth))) }
    /// Width of the expanded panel, in points.
    static var expandedWidth: CGFloat { CGFloat(value(Key.expandedWidth, default: Double(Metrics.expandedWidth))) }
    static var hapticsEnabled: Bool { value(Key.hapticsEnabled, default: true) }
    /// Off: only music apps (see `MediaSourceFilter`). On: browsers and video players too.
    static var showAllMediaSources: Bool { value(Key.showAllMediaSources, default: false) }
    /// Drive the compact visualizer from the actual audio (needs System Audio Recording permission).
    static var realAudioVisualizer: Bool { value(Key.realAudioVisualizer, default: true) }
    /// Take over the volume and brightness keys (needs Accessibility) so Notchi's HUD replaces the system's.
    static var replaceSystemHUD: Bool { value(Key.replaceSystemHUD, default: true) }
    /// Toasts when plugging in and when the battery runs low.
    static var batteryAlerts: Bool { value(Key.batteryAlerts, default: true) }
    /// Off: the notch only opens on click.
    static var openOnHover: Bool { value(Key.openOnHover, default: true) }
    /// Island style only: keep the small capsule visible at rest, like iPhone. Off hides it until needed.
    static var islandVisibleWhenIdle: Bool { value(Key.islandVisibleWhenIdle, default: true) }
    /// Hide the notch while a full-screen app is in front (the volume and brightness HUD still shows).
    static var hideInFullScreen: Bool { value(Key.hideInFullScreen, default: true) }
    /// Show paused Clock timers and a paused stopwatch in compact mode, not just running ones.
    static var clockShowsPaused: Bool { value(Key.clockShowsPaused, default: true) }
    /// Toasts when a Focus turns on or off (needs Accessibility).
    static var focusAlerts: Bool { value(Key.focusAlerts, default: true) }
    static var forceIsland: Bool { value(Key.forceIsland, default: false) }

    /// Reads a stored value, falling back when nothing is stored or registered (tests and previews).
    private static func value<T>(_ key: String, default fallback: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }
}
