import AppKit
import SwiftUI

/// Plays frames (a sprite strip) or a gentle pulse with Core Animation, so the animation runs in the
/// render server instead of Notchi: SwiftUI never redraws for it, and the app's CPU stays near zero
/// while it plays. A SwiftUI frame loop or `symbolEffect(.pulse)` re-renders the view at the
/// display's refresh rate, which cost 3–15% CPU for one small mascot.
///
/// Fills its frame; size and place it from SwiftUI.
struct LayerAnimationView: NSViewRepresentable {
    let frames: [CGImage]
    /// One per frame.
    var durations: [Duration] = []
    /// Scale without smoothing (pixel art).
    var pixelArt = false
    /// Breathes the opacity, for a single image that should look busy.
    var pulses = false
    /// False shows the first frame, still (Reduce Motion).
    var animates = true

    func makeNSView(context: Context) -> LayerHostView { LayerHostView() }

    func updateNSView(_ view: LayerHostView, context: Context) {
        view.show(frames: frames, durations: durations, pixelArt: pixelArt, pulses: pulses, animates: animates)
    }
}

final class LayerHostView: NSView {
    private let content = CALayer()
    /// What's playing, so SwiftUI updates that change nothing don't restart the animation.
    private var playing: [AnyHashable] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        content.contentsGravity = .resize
        layer?.addSublayer(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        content.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// Clicks go to SwiftUI around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(frames: [CGImage], durations: [Duration], pixelArt: Bool, pulses: Bool, animates: Bool) {
        let key: [AnyHashable] = frames.map { ObjectIdentifier($0) } + [pixelArt, pulses, animates]
        guard key != playing else { return }
        playing = key

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.removeAllAnimations()
        content.contents = frames.first
        content.opacity = 1
        content.magnificationFilter = pixelArt ? .nearest : .linear
        content.minificationFilter = pixelArt ? .nearest : .linear
        CATransaction.commit()

        guard animates else { return }
        if frames.count > 1 {
            let seconds = frames.indices.map { index in
                durations.indices.contains(index) ? Self.seconds(durations[index]) : 0.125
            }
            let total = seconds.reduce(0, +)
            // Discrete: each frame holds until the next key time; one more key time than frames.
            var keyTimes: [NSNumber] = [0]
            var elapsed = 0.0
            for duration in seconds {
                elapsed += duration
                keyTimes.append(NSNumber(value: elapsed / total))
            }
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = frames
            animation.keyTimes = keyTimes
            animation.calculationMode = .discrete
            animation.duration = total
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            content.add(animation, forKey: "frames")
        }
        if pulses {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1
            animation.toValue = 0.4
            animation.duration = 0.9
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.isRemovedOnCompletion = false
            content.add(animation, forKey: "pulse")
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

/// An SF Symbol drawn once into an image and shown with `LayerAnimationView`, so it can pulse
/// without SwiftUI redrawing it.
@MainActor
struct LayerSymbol: View {
    let name: String
    let style: AnyShapeStyle
    /// Identifies `style` for the image cache ("orange", "gemini").
    let styleKey: String
    let size: CGFloat
    var weight: Font.Weight = .semibold
    var pulses = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = image {
            LayerAnimationView(frames: [image], pulses: pulses, animates: !reduceMotion)
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    private static var cache: [String: CGImage] = [:]

    private var image: CGImage? {
        let key = "\(name)|\(styleKey)|\(size)|\(weight)|\(displayScale)"
        if let cached = Self.cache[key] { return cached }
        let renderer = ImageRenderer(content:
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .fontWeight(weight)
                .foregroundStyle(style)
                .frame(width: size, height: size)
        )
        renderer.scale = displayScale
        let image = renderer.cgImage
        Self.cache[key] = image
        return image
    }
}
