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
        static let menuBarSafeZone = "menuBarSafeZone"
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
        static let callsShowIncoming = "callsShowIncoming"
        static let callsIncludeBrowsers = "callsIncludeBrowsers"
        static let callsAnnounceEnd = "callsAnnounceEnd"
        static let recordingShowsScreen = "recordingShowsScreen"
        static let recordingShowsMicrophone = "recordingShowsMicrophone"
        /// Debug: draw the Dynamic Island even on a notched display. Launch with `-NotchiForceIsland YES`.
        static let forceIsland = "NotchiForceIsland"
    }

    /// Default values for the settings whose defaults aren't the layout's reference sizes in
    /// `Metrics`. Shared by `registerDefaults`, the accessors below and the views' `@AppStorage`.
    enum Default {
        static let expandDelay = 0.25
        static let collapseDelay = 0.0
        static let compactSideWidth = 42.0
        static let expandedWidth = 530.0
        static let islandVisibleWhenIdle = false
        static let glassClarity = 100.0
        static let edgeHighlight = 30.0
        static let notchBlend = 60.0
        static let notchCornerRadius = 48.0
        static let notchTopCurve = 28.0
        static let compactLip = 0.5
        static let openDuration = 0.15
        static let openBounce = 60.0
        static let agentTintsGlass = false
        static let callsIncludeBrowsers = false
    }

    /// Every key Notchi stores, for "Reset All Settings".
    static let allKeys = [
        Key.expandDelay, Key.collapseDelay, Key.hapticsEnabled, Key.compactSideWidth, Key.expandedWidth,
        Key.showAllMediaSources, Key.realAudioVisualizer, Key.replaceSystemHUD, Key.batteryAlerts,
        Key.focusAlerts, Key.focusActivity, Key.openOnHover, Key.islandVisibleWhenIdle, Key.clockShowsPaused, Key.hideInFullScreen, Key.menuBarSafeZone,
        Key.glassClarity, Key.edgeHighlight, Key.glassStyle, Key.notchBlend, Key.notchCornerRadius, Key.notchTopCurve,
        Key.compactAlignment, Key.compactLip, Key.openAnimation, Key.openDuration, Key.openBounce,
        Key.agentAnnouncesDone, Key.agentShowsStep, Key.agentTintsGlass,
        Key.callsShowIncoming, Key.callsIncludeBrowsers, Key.callsAnnounceEnd, Key.recordingShowsScreen, Key.recordingShowsMicrophone,
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.expandDelay: Default.expandDelay,
            Key.collapseDelay: Default.collapseDelay,
            Key.hapticsEnabled: true,
            Key.compactSideWidth: Default.compactSideWidth,
            Key.expandedWidth: Default.expandedWidth,
            Key.showAllMediaSources: false,
            Key.realAudioVisualizer: true,
            Key.replaceSystemHUD: true,
            Key.batteryAlerts: true,
            Key.focusAlerts: true,
            Key.focusActivity: false,
            Key.openOnHover: true,
            Key.islandVisibleWhenIdle: Default.islandVisibleWhenIdle,
            Key.clockShowsPaused: true,
            Key.hideInFullScreen: true,
            Key.menuBarSafeZone: true,
            Key.glassClarity: Default.glassClarity,
            Key.edgeHighlight: Default.edgeHighlight,
            Key.glassStyle: GlassStyle.clear.rawValue,
            Key.notchBlend: Default.notchBlend,
            Key.notchCornerRadius: Default.notchCornerRadius,
            Key.notchTopCurve: Default.notchTopCurve,
            Key.compactAlignment: CompactAlignment.center.rawValue,
            Key.compactLip: Default.compactLip,
            Key.openAnimation: OpenAnimation.snappy.rawValue,
            Key.openDuration: Default.openDuration,
            Key.openBounce: Default.openBounce,
            Key.agentAnnouncesDone: true,
            Key.agentShowsStep: false,
            Key.agentTintsGlass: Default.agentTintsGlass,
            Key.callsShowIncoming: true,
            Key.callsIncludeBrowsers: Default.callsIncludeBrowsers,
            Key.callsAnnounceEnd: true,
            Key.recordingShowsScreen: true,
            Key.recordingShowsMicrophone: true,
            Key.forceIsland: false,
        ])
    }

    /// Hover dwell before expanding, so passing the cursor over the notch doesn't open it.
    static var expandDelay: Double { value(Key.expandDelay, default: Default.expandDelay) }
    /// Grace period after the cursor leaves before collapsing.
    static var collapseDelay: Double { value(Key.collapseDelay, default: Default.collapseDelay) }
    /// Width of each compact slot beside the notch, in points.
    static var compactSideWidth: CGFloat { CGFloat(value(Key.compactSideWidth, default: Default.compactSideWidth)) }
    /// Width of the expanded panel, in points.
    static var expandedWidth: CGFloat { CGFloat(value(Key.expandedWidth, default: Default.expandedWidth)) }
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
    static var islandVisibleWhenIdle: Bool { value(Key.islandVisibleWhenIdle, default: Default.islandVisibleWhenIdle) }
    /// Hide the notch while a full-screen app is in front (the volume and brightness HUD still shows).
    static var hideInFullScreen: Bool { value(Key.hideInFullScreen, default: true) }
    /// The live activity tucks back into the notch while the pointer is on the menu bar icons it covers.
    static var menuBarSafeZone: Bool { value(Key.menuBarSafeZone, default: true) }
    /// Show paused Clock timers and a paused stopwatch in compact mode, not just running ones.
    static var clockShowsPaused: Bool { value(Key.clockShowsPaused, default: true) }
    /// Announce in the notch when a Focus turns on or off (needs Accessibility).
    static var focusAlerts: Bool { value(Key.focusAlerts, default: true) }
    /// Keep an active Focus in the notch as a quiet live activity (needs Accessibility).
    static var focusActivity: Bool { value(Key.focusActivity, default: false) }
    /// How see-through the surface is, in percent: 0 is solid black, 100 is as clear as the glass gets.
    static var glassClarity: Double { value(Key.glassClarity, default: Default.glassClarity) }
    /// Brightness of the light rim around the surface, in percent. 0 turns it off.
    static var edgeHighlight: Double { value(Key.edgeHighlight, default: Default.edgeHighlight) }
    /// How far the notch's black fades out into the glass, in points (notch style only).
    static var notchBlend: Double { value(Key.notchBlend, default: Default.notchBlend) }
    /// Bottom corner radius of the opened notch, in points (compact scales along).
    static var notchCornerRadius: CGFloat {
        CGFloat(value(Key.notchCornerRadius, default: Default.notchCornerRadius))
    }
    /// Radius of the concave curves where the opened notch meets the top bezel, in points.
    static var notchTopCurve: CGFloat {
        CGFloat(value(Key.notchTopCurve, default: Default.notchTopCurve))
    }
    /// How the notch springs open.
    static var openAnimation: OpenAnimation {
        OpenAnimation(rawValue: value(Key.openAnimation, default: "")) ?? .snappy
    }
    /// Custom open animation: spring response, in seconds.
    static var openDuration: Double { value(Key.openDuration, default: Default.openDuration) }
    /// Custom open animation: overshoot, in percent (0 is none).
    static var openBounce: Double { value(Key.openBounce, default: Default.openBounce) }
    /// Where live activity content sits in the compact slots beside the notch.
    static var compactAlignment: CompactAlignment {
        CompactAlignment(rawValue: value(Key.compactAlignment, default: "")) ?? .center
    }
    /// A short "Done" toast when a coding agent finishes a request.
    static var agentAnnouncesDone: Bool { value(Key.agentAnnouncesDone, default: true) }
    /// A row under the notch with what a running agent is doing ("Editing NotchShape.swift").
    static var agentShowsStep: Bool { value(Key.agentShowsStep, default: false) }
    /// The notch's glass takes on the color of the agent in it.
    static var agentTintsGlass: Bool { value(Key.agentTintsGlass, default: Default.agentTintsGlass) }
    /// A FaceTime or iPhone call ringing takes the middle of the notch (needs Accessibility).
    static var callsShowIncoming: Bool { value(Key.callsShowIncoming, default: true) }
    /// A browser using the microphone counts as a call (Meet, Teams on the web).
    static var callsIncludeBrowsers: Bool { value(Key.callsIncludeBrowsers, default: Default.callsIncludeBrowsers) }
    /// A short "Ended" toast when a call ends.
    static var callsAnnounceEnd: Bool { value(Key.callsAnnounceEnd, default: true) }
    /// A red dot and the time while the screen is recorded or shared.
    static var recordingShowsScreen: Bool { value(Key.recordingShowsScreen, default: true) }
    /// An orange mic and the time while an app (not a call) records from the microphone.
    static var recordingShowsMicrophone: Bool { value(Key.recordingShowsMicrophone, default: true) }
    /// How far the closed notch reaches below the physical one while it shows a live activity, in
    /// points: 0 is flush with the camera housing.
    static var compactLip: CGFloat { CGFloat(value(Key.compactLip, default: Default.compactLip)) }
    static var forceIsland: Bool { value(Key.forceIsland, default: false) }

    /// Reads a stored value, falling back when nothing is stored or registered (tests and previews).
    private static func value<T>(_ key: String, default fallback: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }
}
