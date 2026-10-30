import SwiftUI

/// The black surface's outline, in either style.
///
/// - Notch: flat top with small concave "ears" that flare into the top bezel, and rounded bottom
///   corners, so the surface reads as the hardware notch growing.
/// - Island: a continuous-corner rounded rectangle (a capsule when the radius is half the height).
///
/// Both radii are animatable, so the corners morph smoothly as the surface grows.
struct NotchShape: Shape {
    var style: NotchGeometry.Style
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        switch style {
        case .island:
            let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        case .notch:
            return notchPath(in: rect)
        }
    }

    private func notchPath(in rect: CGRect) -> Path {
        let ear = max(0, min(topRadius, rect.width / 4, rect.height / 2))
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * ear) / 2, rect.height - ear))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left ear: curves from the bezel line down into the left wall.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
            control: CGPoint(x: rect.minX + ear, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - bottom))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + ear, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX + ear + bottom, y: rect.maxY),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: rect.maxX - ear - bottom, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - ear, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - ear, y: rect.maxY - bottom),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        // Right ear: mirror of the left.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - ear, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Notch shape") {
    VStack(spacing: 24) {
        NotchShape(style: .notch, topRadius: 6, bottomRadius: 12)
            .frame(width: 269, height: 32)
        NotchShape(style: .notch, topRadius: 14, bottomRadius: 32)
            .frame(width: 460, height: 172)
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}

#Preview("Island shape") {
    VStack(spacing: 24) {
        NotchShape(style: .island, topRadius: 0, bottomRadius: 16)
            .frame(width: 192, height: 32)
        NotchShape(style: .island, topRadius: 0, bottomRadius: 34)
            .frame(width: 460, height: 178)
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
