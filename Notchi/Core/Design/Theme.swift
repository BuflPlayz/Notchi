import SwiftUI

/// Colors and type for content drawn on the notch.
///
/// The surface is pure black where it meets the hardware and fades to dark glass below,
/// in light and dark mode alike, so content is always light-on-dark.
enum Theme {
    static let surface = Color.black

    /// Black laid over the glass, top to bottom: darkest under the menu bar, thinning toward the bottom.
    /// `clarity` runs from 0 (solid black) to 1, where the bottom is bare glass.
    static func glassTint(clarity: Double) -> [Gradient.Stop] {
        [
            .init(color: .black.opacity(1 - 0.7 * clarity), location: 0),
            .init(color: .black.opacity(1 - 0.88 * clarity), location: 0.5),
            .init(color: .black.opacity(1 - clarity), location: 1),
        ]
    }

    /// Faint white lift at the bottom, so the glass reads lighter rather than just less black.
    static func glassSheen(clarity: Double) -> Color { .white.opacity(0.08 * clarity) }

    /// A color laid over the glass, faint at the top and fuller at the bottom.
    static func glassColor(_ tint: Color) -> [Color] {
        [tint.opacity(0.12), tint.opacity(0.32)]
    }

    /// Light catching the surface's edge, dimmer at the top than the bottom. `brightness` runs from 0 to 1.
    static func glassRim(brightness: Double) -> [Color] {
        [.white.opacity(0.2 * brightness), .white.opacity(0.4 * brightness)]
    }
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.35)
    /// Fill for controls sitting on the surface.
    static let controlFill = Color.white.opacity(0.1)
    static let controlFillPressed = Color.white.opacity(0.18)

    static let title = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11, weight: .medium)
}

/// Pill-shaped button that sits on the black surface.
struct NotchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body.weight(.medium))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(configuration.isPressed ? Theme.controlFillPressed : Theme.controlFill)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round icon button for the expanded header.
struct NotchIconButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? Theme.primary : Theme.secondary)
            .frame(width: 26, height: 26)
            .background(
                Circle().fill(isSelected || configuration.isPressed ? Theme.controlFill : .clear)
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Matched geometry

extension EnvironmentValues {
    /// Shared namespace so modules can fly views between compact and expanded content.
    /// `nil` when Reduce Motion is on, which turns matched-geometry flights off.
    @Entry var notchNamespace: Namespace.ID? = nil
}

extension View {
    /// Matches this view with the same `id` across compact and expanded content, when motion allows.
    func notchMatchedGeometry(id: String) -> some View {
        modifier(NotchMatchedGeometry(id: id))
    }
}

private struct NotchMatchedGeometry: ViewModifier {
    let id: String
    @Environment(\.notchNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

#Preview("Buttons") {
    HStack(spacing: 12) {
        Button("Start") {}.buttonStyle(NotchButtonStyle())
        Button {} label: { Image(systemName: "sparkles") }
            .buttonStyle(NotchIconButtonStyle(isSelected: true))
        Button {} label: { Image(systemName: "timer") }
            .buttonStyle(NotchIconButtonStyle())
    }
    .padding(24)
    .background(Theme.surface)
}
