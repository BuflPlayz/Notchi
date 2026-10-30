import SwiftUI

/// A detached round bubble beside the compact notch, holding another live activity's glyph.
/// Clicking it swaps that activity into the middle.
struct SatelliteBubble: View {
    let module: any NotchModule
    let diameter: CGFloat
    let action: () -> Void
    @AppStorage(Preferences.Key.glassClarity) private var glassClarity = 85.0
    @AppStorage(Preferences.Key.glassStyle) private var glassStyle = GlassStyle.clear
    @AppStorage(Preferences.Key.edgeHighlight) private var edgeHighlight = 60.0

    var body: some View {
        Button(action: action) {
            module.compactMinimal()
                // No matched-geometry flights in here: artwork flying in from the notch's slot would
                // swing around inside the circle, behind the bubble's own warp.
                .environment(\.notchNamespace, nil)
                .frame(width: diameter, height: diameter)
                .background { NotchSurface(shape: Circle(), notch: nil, clarity: glassClarity / 100, glass: glassStyle) }
                .clipShape(Circle())
                .overlay { NotchRim(shape: Circle(), style: .island, brightness: edgeHighlight / 100) }
                .contentShape(Circle())
        }
        .buttonStyle(SatelliteButtonStyle())
        .foregroundStyle(Theme.primary)
        .help(module.title)
    }
}

/// Squeezes the bubble a little while pressed.
private struct SatelliteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(Motion.content, value: configuration.isPressed)
    }
}

/// The warp a bubble goes through as it merges into the surface (`progress` 1) or is squeezed back
/// out of it (toward 0): it's pulled in toward the notch, stretching along the way like a drop of
/// liquid, and blurs out as it meets the surface.
///
/// Animatable, so the curves below run per frame instead of being blended linearly. A spring
/// overshooting below 0 makes a freshly squeezed-out bubble wobble, at half strength.
nonisolated struct SatelliteWarp: ViewModifier, Animatable {
    let side: SatelliteSide
    /// How far toward the notch's center the bubble travels when fully absorbed.
    let travel: CGFloat
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let toward = -side.sign
        let warp = progress < 0 ? progress / 2 : progress
        content
            // Anchored on the far side, so the stretch reaches toward the notch.
            .scaleEffect(x: 1 + 0.7 * warp, y: 1 - 0.55 * warp, anchor: side == .leading ? .leading : .trailing)
            .offset(x: toward * travel * warp)
            .blur(radius: 5 * progress * progress)
            .opacity(min(1, 1 - progress * progress * progress))
    }
}

/// The surface's gulp when a bubble swaps in: a quick wide squash, then a springy settle.
struct SwapPulse {
    var stretch: CGFloat = 1
    var squash: CGFloat = 1
}

extension View {
    /// Plays `SwapPulse` each time `trigger` changes. Anchored at the top, so the notch stays put.
    func swapPulse(trigger: Int) -> some View {
        keyframeAnimator(initialValue: SwapPulse(), trigger: trigger) { content, pulse in
            content.scaleEffect(x: pulse.stretch, y: pulse.squash, anchor: .top)
        } keyframes: { _ in
            KeyframeTrack(\.stretch) {
                CubicKeyframe(1.06, duration: 0.13)
                SpringKeyframe(1, duration: 0.55, spring: Spring(response: 0.4, dampingRatio: 0.5))
            }
            KeyframeTrack(\.squash) {
                CubicKeyframe(0.9, duration: 0.13)
                SpringKeyframe(1, duration: 0.55, spring: Spring(response: 0.4, dampingRatio: 0.5))
            }
        }
    }
}
