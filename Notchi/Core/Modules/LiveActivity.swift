import SwiftUI

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
    /// Extra height for a full-width row below the notch (see `NotchModule.compactBelow()`), for
    /// content that belongs to neither side, like the HUD's level bar. 0 keeps compact one row high.
    var belowHeight: CGFloat = 0
    /// A color the glass takes on while this activity has the middle (and in its bubble), like an
    /// agent's own color. Nil keeps the glass as the user set it.
    var surfaceTint: Color? = nil
}
