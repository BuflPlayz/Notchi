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
        static let focusActivity = "focusActivity"
        static let openOnHover = "openOnHover"
        static let islandVisibleWhenIdle = "islandVisibleWhenIdle"
        static let clockShowsPaused = "clockShowsPaused"
        static let hideInFullScreen = "hideInFullScreen"
        static let glassClarity = "glassClarity"
        static let edgeHighlight = "edgeHighlight"
        static let glassStyle = "glassStyle"
        static let notchBlend = "notchBlend"
        static let notchCornerRadius = "notchCornerRadius"
        static let notchTopCurve = "notchTopCurve"
        static let compactAlignment = "compactAlignment"
        static let compactLip = "compactLip"
        static let openAnimation = "openAnimation"
        static let openDuration = "openDuration"
        static let openBounce = "openBounce"
        static let agentAnnouncesDone = "agentAnnouncesDone"
        static let agentShowsStep = "agentShowsStep"
        static let agentTintsGlass = "agentTintsGlass"
        /// Debug: draw the Dynamic Island even on a notched display. Launch with `-NotchiForceIsland YES`.
        static let forceIsland = "NotchiForceIsland"
    }

    /// Every key Notchi stores, for "Reset All Settings".
    static let allKeys = [
        Key.expandDelay, Key.collapseDelay, Key.hapticsEnabled, Key.compactSideWidth, Key.expandedWidth,
        Key.showAllMediaSources, Key.realAudioVisualizer, Key.replaceSystemHUD, Key.batteryAlerts,
        Key.focusAlerts, Key.focusActivity, Key.openOnHover, Key.islandVisibleWhenIdle, Key.clockShowsPaused, Key.hideInFullScreen,
        Key.glassClarity, Key.edgeHighlight, Key.glassStyle, Key.notchBlend, Key.notchCornerRadius, Key.notchTopCurve,
        Key.compactAlignment, Key.compactLip, Key.openAnimation, Key.openDuration, Key.openBounce,
        Key.agentAnnouncesDone, Key.agentShowsStep, Key.agentTintsGlass,
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
            Key.focusActivity: false,
            Key.openOnHover: true,
            Key.islandVisibleWhenIdle: true,
            Key.clockShowsPaused: true,
            Key.hideInFullScreen: true,
            Key.glassClarity: 85.0,
            Key.edgeHighlight: 60.0,
            Key.glassStyle: GlassStyle.clear.rawValue,
            Key.notchBlend: Double(Metrics.Notch.hardwareBlend),
            Key.notchCornerRadius: Double(Metrics.Notch.expandedBottomRadius),
            Key.notchTopCurve: Double(Metrics.Notch.expandedTopRadius),
            Key.compactAlignment: CompactAlignment.center.rawValue,
            Key.compactLip: Double(Metrics.Notch.compactBottomLip),
            Key.openAnimation: OpenAnimation.snappy.rawValue,
            Key.openDuration: 0.35,
            Key.openBounce: 22.0,
            Key.agentAnnouncesDone: true,
            Key.agentShowsStep: false,
            Key.agentTintsGlass: true,
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
    /// Announce in the notch when a Focus turns on or off (needs Accessibility).
    static var focusAlerts: Bool { value(Key.focusAlerts, default: true) }
    /// Keep an active Focus in the notch as a quiet live activity (needs Accessibility).
    static var focusActivity: Bool { value(Key.focusActivity, default: false) }
    /// How see-through the surface is, in percent: 0 is solid black, 100 is as clear as the glass gets.
    static var glassClarity: Double { value(Key.glassClarity, default: 85.0) }
    /// Brightness of the light rim around the surface, in percent. 0 turns it off.
    static var edgeHighlight: Double { value(Key.edgeHighlight, default: 60.0) }
    /// How far the notch's black fades out into the glass, in points (notch style only).
    static var notchBlend: Double { value(Key.notchBlend, default: Double(Metrics.Notch.hardwareBlend)) }
    /// Bottom corner radius of the opened notch, in points (compact scales along).
    static var notchCornerRadius: CGFloat {
        CGFloat(value(Key.notchCornerRadius, default: Double(Metrics.Notch.expandedBottomRadius)))
    }
    /// Radius of the concave curves where the opened notch meets the top bezel, in points.
    static var notchTopCurve: CGFloat {
        CGFloat(value(Key.notchTopCurve, default: Double(Metrics.Notch.expandedTopRadius)))
    }
    /// How the notch springs open.
    static var openAnimation: OpenAnimation {
        OpenAnimation(rawValue: value(Key.openAnimation, default: "")) ?? .snappy
    }
    /// Custom open animation: spring response, in seconds.
    static var openDuration: Double { value(Key.openDuration, default: 0.35) }
    /// Custom open animation: overshoot, in percent (0 is none).
    static var openBounce: Double { value(Key.openBounce, default: 22.0) }
    /// Where live activity content sits in the compact slots beside the notch.
    static var compactAlignment: CompactAlignment {
        CompactAlignment(rawValue: value(Key.compactAlignment, default: "")) ?? .center
    }
    /// A short "Done" toast when a coding agent finishes a request.
    static var agentAnnouncesDone: Bool { value(Key.agentAnnouncesDone, default: true) }
    /// A row under the notch with what a running agent is doing ("Editing NotchShape.swift").
    static var agentShowsStep: Bool { value(Key.agentShowsStep, default: false) }
    /// The notch's glass takes on the color of the agent in it.
    static var agentTintsGlass: Bool { value(Key.agentTintsGlass, default: true) }
    /// How far the closed notch reaches below the physical one while it shows a live activity, in
    /// points: 0 is flush with the camera housing.
    static var compactLip: CGFloat { CGFloat(value(Key.compactLip, default: Double(Metrics.Notch.compactBottomLip))) }
    static var forceIsland: Bool { value(Key.forceIsland, default: false) }

    /// Reads a stored value, falling back when nothing is stored or registered (tests and previews).
    private static func value<T>(_ key: String, default fallback: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }
}
