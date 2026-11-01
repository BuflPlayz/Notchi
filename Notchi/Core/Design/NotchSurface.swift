import AppKit
import SwiftUI

/// The surface's fill: Liquid Glass under a black tint that is darkest at the top and thins toward
/// the bottom, like Siri and Spotlight.
///
/// In notch style the camera housing's black feathers out into the glass, so the hardware edge
/// never shows as a seam, whether the surface is compact or expanded.
struct NotchSurface<S: Shape>: View {
    let shape: S
    /// The physical notch, centered at the top of the surface. `nil` for the island.
    let notch: CGSize?
    /// 0 is solid black, 1 is as clear as the glass gets.
    let clarity: Double
    var glass: GlassStyle = .clear
    /// How far the notch's black feathers out into the glass, in points.
    var blend: CGFloat = Metrics.Notch.hardwareBlend
    /// A color the glass takes on (a live activity's own), or nil.
    var tint: Color? = nil

    var body: some View {
        ZStack {
            LinearGradient(stops: Theme.glassTint(clarity: clarity), startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.clear, Theme.glassSheen(clarity: clarity)], startPoint: .top, endPoint: .bottom)
            // Over the black, so the color shows even where the glass is darkest; strongest at the
            // bottom, like light coming up through the glass. Static layers: nothing redraws per frame.
            LinearGradient(colors: Theme.glassColor(tint ?? .clear), startPoint: .top, endPoint: .bottom)
                .opacity(tint == nil ? 0 : 1)
        }
        // An overlay, so the blend's overhang never changes the surface's size.
        .overlay(alignment: .top) {
            if let notch { HardwareBlend(notch: notch, feather: blend) }
        }
        .background { GlassBackdrop(shape: shape, style: glass, tint: tint) }
    }
}

/// Apple's two Liquid Glass variants.
enum GlassStyle: String, CaseIterable, Identifiable {
    /// Frosted: blurs and dims what's behind, so content reads anywhere.
    case regular
    /// Barely there: what's behind stays sharp and refracts at the edges.
    case clear

    var id: Self { self }

    var title: String {
        switch self {
        case .regular: "Frosted"
        case .clear: "Clear"
        }
    }
}

/// Light catching the surface's edge.
///
/// Drawn centered on the outline and outside the clip, so its outer half still shows where the
/// surface runs along the hardware notch (the compact notch's bottom edge, for one).
struct NotchRim<S: Shape>: View {
    let shape: S
    let style: NotchGeometry.Style
    /// 0 turns the rim off, 1 is its brightest.
    let brightness: Double
    /// Notch style: fades the outline out where it would run under the physical notch.
    var notchFade: NotchRimFade? = nil

    var body: some View {
        let overhang: CGFloat = 2
        shape
            .stroke(
                LinearGradient(colors: Theme.glassRim(brightness: brightness), startPoint: .top, endPoint: .bottom),
                lineWidth: 1.5
            )
            .mask {
                // Notch style: leave out the flat top edge, which would draw a line along the bezel.
                VStack(spacing: 0) {
                    Color.clear.frame(height: style == .notch ? overhang + 1 : 0)
                    Color.black
                }
                .padding(-overhang)
            }
            .mask {
                if let notchFade {
                    LinearGradient(stops: notchFade.stops(overhang: overhang), startPoint: .leading, endPoint: .trailing)
                        .padding(-overhang)
                } else {
                    Color.black.padding(-overhang)
                }
            }
            .opacity(brightness > 0 ? 1 : 0)
            .allowsHitTesting(false)
    }
}

/// Where the surface's bottom edge runs under the physical notch, the camera housing hides it, and
/// the outline would stop dead at the housing's sides. This fades it out on the way there instead,
/// as much as the bottom edge is hidden: fully when the surface is flush with the notch, not at all
/// once it reaches `compactBottomLip` below it.
struct NotchRimFade: Equatable {
    var notchWidth: CGFloat
    var shapeWidth: CGFloat
    /// How much of the outline shows below the notch: 0 hides it, 1 leaves it whole.
    var centerOpacity: Double

    /// For a surface `height` tall over a notch of `notch` size.
    init(notch: CGSize, shapeWidth: CGFloat, height: CGFloat) {
        notchWidth = notch.width
        self.shapeWidth = shapeWidth
        centerOpacity = Double(min(max((height - notch.height) / Metrics.Notch.compactBottomLip, 0), 1))
    }

    /// Mask stops across the rim, which reaches `overhang` past the shape on each side.
    func stops(overhang: CGFloat) -> [Gradient.Stop] {
        let total = shapeWidth + 2 * overhang
        guard total > 0, notchWidth < shapeWidth else { return [.init(color: .black, location: 0), .init(color: .black, location: 1)] }
        let notchEdge = (shapeWidth - notchWidth) / 2 + overhang
        let fadeStart = max(0, notchEdge - Metrics.Notch.rimFadeLength)
        let center = Color.black.opacity(centerOpacity)
        return [
            .init(color: .black, location: 0),
            .init(color: .black, location: fadeStart / total),
            .init(color: center, location: notchEdge / total),
            .init(color: center, location: (total - notchEdge) / total),
            .init(color: .black, location: (total - fadeStart) / total),
            .init(color: .black, location: 1),
        ]
    }
}

/// Black that continues the camera housing: solid over the notch itself, then fading out into the
/// glass over `feather` points.
private struct HardwareBlend: View {
    let notch: CGSize
    let feather: CGFloat

    var body: some View {
        let radius = Metrics.Notch.hardwareBottomRadius
        ZStack(alignment: .top) {
            if feather > 0 {
                // Grown by half the fade (and pushed above the top edge so that edge stays solid),
                // then blurred so it's still black at the notch's edge and gone `feather` beyond it.
                UnevenRoundedRectangle(
                    bottomLeadingRadius: radius + feather / 2,
                    bottomTrailingRadius: radius + feather / 2,
                    style: .continuous
                )
                .fill(Theme.surface)
                .frame(width: notch.width + feather, height: notch.height + feather)
                .offset(y: -feather / 2)
                .blur(radius: feather / 4)
            }
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                .fill(Theme.surface)
                .frame(width: notch.width, height: notch.height)
        }
        .allowsHitTesting(false)
    }
}

/// Blurs whatever is behind the panel: Liquid Glass where available, a HUD material before that
/// (in either style).
private struct GlassBackdrop<S: Shape>: View {
    let shape: S
    let style: GlassStyle
    var tint: Color?

    var body: some View {
        if #available(macOS 26, *) {
            let glass: Glass = style == .clear ? .clear : .regular
            Color.clear.glassEffect(glass.tint(tint?.opacity(0.35)), in: shape)
        } else {
            BehindWindowBlur()
        }
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassthroughEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active    // the panel never becomes key, so follow-window-state would look inactive
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    /// Leaves clicks to the SwiftUI content on top.
    private final class PassthroughEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

#Preview("Glass surface") {
    let shape = NotchShape(style: .notch, topRadius: 14, bottomRadius: 32)
    return ZStack(alignment: .top) {
        LinearGradient(colors: [.orange, .pink, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        Text("The surface fades to glass")
            .font(Theme.title)
            .foregroundStyle(Theme.primary)
            .frame(width: 460, height: 172)
            .background { NotchSurface(shape: shape, notch: CGSize(width: 188, height: 32), clarity: 0.85) }
            .clipShape(shape)
            .overlay { NotchRim(shape: shape, style: .notch, brightness: 0.6) }
    }
    .frame(width: 560, height: 240)
}
