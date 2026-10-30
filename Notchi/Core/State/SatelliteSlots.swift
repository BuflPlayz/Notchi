import CoreGraphics

/// Which side of the notch a detached activity bubble sits on.
enum SatelliteSide: CaseIterable, Sendable {
    case leading
    case trailing

    /// −1 left of the notch, +1 right of it.
    var sign: CGFloat { self == .leading ? -1 : 1 }
}

/// The bubbles beside the compact notch: other live activities waiting their turn, like the
/// iPhone's Dynamic Island when two activities run at once.
///
/// Slots are sticky. A bubble keeps its side while its activity lasts, and when the user swaps one
/// into the middle, the activity it replaces takes its exact slot, so nothing shuffles around.
struct SatelliteSlots: Equatable, Sendable {
    var leading: String?
    var trailing: String?

    subscript(side: SatelliteSide) -> String? {
        get { side == .leading ? leading : trailing }
        set { if side == .leading { leading = newValue } else { trailing = newValue } }
    }

    func side(of id: String) -> SatelliteSide? {
        SatelliteSide.allCases.first { self[$0] == id }
    }

    /// Occupied sides, leading first.
    var occupied: [SatelliteSide] {
        SatelliteSide.allCases.filter { self[$0] != nil }
    }

    /// Keeps bubbles whose activity is still a candidate where they are, drops the rest, and fills
    /// free slots from `candidates` (most important first). A lone bubble goes on the trailing
    /// side, as on iPhone. Candidates beyond two only show in the expanded panel.
    func reconciled(with candidates: [String]) -> SatelliteSlots {
        var slots = self
        for side in SatelliteSide.allCases where slots[side].map({ !candidates.contains($0) }) == true {
            slots[side] = nil
        }
        for id in candidates where slots.side(of: id) == nil {
            if slots.trailing == nil {
                slots.trailing = id
            } else if slots.leading == nil {
                slots.leading = id
            }
        }
        return slots
    }
}
