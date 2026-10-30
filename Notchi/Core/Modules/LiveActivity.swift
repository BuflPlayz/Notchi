import CoreGraphics

/// A module's request for compact-mode space beside the notch.
struct LiveActivity: Equatable, Sendable {
    /// Higher priorities take the compact slots. Ties go to the module registered first.
    enum Priority: Int, Comparable, Sendable {
        /// Background state, such as a paused track.
        case ambient
        /// Something running, such as music playing or a timer counting.
        case active
        /// Needs attention soon, such as a timer's last seconds.
        case urgent
        /// Short-lived toasts and HUDs (plug-in, volume). The module clears them itself.
        case transient

        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var priority: Priority
    /// Width of each compact slot. `nil` uses the user's "Live activity width" setting;
    /// modules whose content can't fit (a timer readout) can ask for a specific width.
    var sideWidth: CGFloat? = nil
    /// Still show while a full-screen app hides the notch. Only for feedback the user just asked
    /// for, like the volume HUD, since the system's own HUD is suppressed.
    var showsInFullScreen = false
}
