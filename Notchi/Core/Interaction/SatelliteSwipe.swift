import CoreGraphics

/// Press and swipe on the compact notch toward a bubble to swap that activity into the middle, as
/// on iPhone. This decides which way a swipe points; the notch's gesture reports it.
enum SatelliteSwipe {
    /// How far the pointer has to travel sideways before a release counts as a swipe.
    static let distance: CGFloat = 24
    /// A quick flick counts sooner, by where it would have coasted to.
    static let flickDistance: CGFloat = 60
    /// Movement under this, press to release, is a click.
    static let clickSlop: CGFloat = 4
    /// The furthest the content leans toward the swipe while the pointer is down.
    static let maxLean: CGFloat = 10

    /// The side a released swipe points at, or nil when it's too short or mostly vertical.
    static func side(translation: CGSize, predictedEnd: CGSize) -> SatelliteSide? {
        let dx = translation.width
        guard abs(dx) > abs(translation.height) else { return nil }
        let travelled = abs(dx) >= distance
        let flicked = abs(predictedEnd.width) >= flickDistance && predictedEnd.width.sign == dx.sign && abs(dx) >= clickSlop
        guard travelled || flicked else { return nil }
        return dx < 0 ? .leading : .trailing
    }

    /// True when press to release moved so little it's a click.
    static func isClick(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) < clickSlop
    }

    /// How far the content leans while the pointer is down: it follows at first, then resists, and
    /// never passes `maxLean`. Less toward a side with nothing to swap in.
    static func lean(for dx: CGFloat, hasTarget: Bool) -> CGFloat {
        let limit = hasTarget ? maxLean : maxLean / 3
        return limit * tanh(dx / (limit * 3))
    }
}
