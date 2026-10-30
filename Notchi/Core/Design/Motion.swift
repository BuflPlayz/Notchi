import AppKit
import SwiftUI

/// Animation presets. Every notch transition goes through here so Reduce Motion is respected everywhere.
@MainActor
enum Motion {
    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Opening: the spring the user picked in Settings (a hint of overshoot by default).
    static var expand: Animation {
        let spring = Preferences.openAnimation.spring
        return reduceMotion ? .easeOut(duration: 0.2) : .spring(response: spring.response, dampingFraction: spring.damping)
    }

    /// Closing: same speed, no overshoot, so the surface settles cleanly back into the notch.
    static var collapse: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.92)
    }

    /// Volume and brightness HUD updates: quick and soft, so rapid key repeats glide.
    static var hud: Animation {
        reduceMotion ? .linear(duration: 0.08) : .spring(response: 0.24, dampingFraction: 0.86)
    }

    /// Small in-place changes (switching modules, compact content swaps).
    static var content: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85)
    }

    /// Swapping a bubble into the middle: quick, with a little give, like the Dynamic Island.
    static var swap: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.8)
    }

    /// Whether a toast taking over compact mode closes the notch and reopens it, instead of just
    /// changing the content in place.
    static var reopensForToasts: Bool { !reduceMotion }

    /// The quick close before a reopen: no overshoot, so it tucks cleanly into the notch.
    static let reopenClose = Animation.spring(response: 0.2, dampingFraction: 1)

    /// How long the notch stays closed before reopening with the new content (`expand`).
    static let reopenBeat: Duration = .milliseconds(170)

    /// A bubble being absorbed into the surface: quick, no overshoot.
    static var satelliteAbsorb: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.95)
    }

    /// A bubble squeezed out of the surface: a small overshoot, so it settles with one soft wobble.
    static var satelliteEmerge: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.76)
    }

    /// How long a swap waits between absorbing the clicked bubble and squeezing out the one it replaces.
    static let swapBeat: Duration = .milliseconds(120)

    /// A bubble beside the notch merges into the surface and squeezes back out of it. Reduce Motion
    /// fades in place. Timing comes from the caller (`satelliteAbsorb`, `satelliteEmerge`): an
    /// animation attached to this transition held insertions back until removals had finished.
    static func satelliteTransition(side: SatelliteSide, travel: CGFloat, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .modifier(
            active: SatelliteWarp(side: side, travel: travel, progress: 1),
            identity: SatelliteWarp(side: side, travel: travel, progress: 0)
        )
    }

    /// How compact and expanded content appear. Blur-in normally, plain fade with Reduce Motion.
    static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .scale(scale: 0.92, anchor: .top))
    }
}

/// How the notch springs open. Closing always settles without overshoot.
enum OpenAnimation: String, CaseIterable, Identifiable {
    /// No overshoot: glides open and stops.
    case smooth
    /// A hint of overshoot. The default.
    case snappy
    /// Overshoots and settles with a small bounce.
    case bouncy
    /// Overshoots far and wobbles before settling.
    case elastic
    /// The user's own duration and bounce.
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .smooth: "Smooth"
        case .snappy: "Snappy"
        case .bouncy: "Bouncy"
        case .elastic: "Elastic"
        case .custom: "Custom"
        }
    }

    /// Spring response (roughly the duration, in seconds) and damping fraction (1 means no overshoot).
    @MainActor var spring: (response: Double, damping: Double) {
        switch self {
        case .smooth: (0.4, 1)
        case .snappy: (0.35, 0.78)
        case .bouncy: (0.42, 0.62)
        case .elastic: (0.5, 0.5)
        case .custom: (Preferences.openDuration, 1 - Preferences.openBounce / 100)
        }
    }

    /// Range of the custom "Duration" setting, in seconds.
    static let durationRange: ClosedRange<CGFloat> = 0.15...0.8
    /// Range of the custom "Bounce" setting, in percent. The top end overshoots by about a quarter
    /// of the distance, which `Metrics.panelMargin` leaves room for.
    static let bounceRange: ClosedRange<CGFloat> = 0...60
}
