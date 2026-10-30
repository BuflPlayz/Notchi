import CoreGraphics

/// The shape's size, radii and content insets for one state.
///
/// A plain value: SwiftUI animates between two layouts, and the window controller
/// turns a layout into a panel frame. Nothing here touches AppKit, so it's fully testable.
struct NotchLayout: Equatable, Sendable {
    /// Total shape size, including the concave ears in notch style.
    var size: CGSize
    /// Gap between the top of the screen and the shape (island only).
    var topInset: CGFloat
    /// Concave ear radius (notch style). Unused for the island.
    var topRadius: CGFloat
    /// Bottom corner radius (notch) or corner radius on all four corners (island).
    var bottomRadius: CGFloat
    /// Horizontal space content must keep clear of on each side (ears or capsule ends).
    var horizontalInset: CGFloat
    /// Space between the left and right compact slots. Matches the physical notch in notch style.
    var centerGap: CGFloat
    /// Height of the header band in the expanded panel.
    var headerHeight: CGFloat
    /// Extra window room around the shape for a drop shadow.
    var shadowPadding: CGFloat
    /// Empty band below the header that only shows the surface's bottom edge (compact notch).
    var bottomLip: CGFloat = 0

    /// - Parameters:
    ///   - sideWidth: Width of each compact slot (user setting, or a module's own request).
    ///   - expandedWidth: Width of the expanded panel (user setting).
    ///   - belowHeight: Compact only: extra height for a full-width row below the notch.
    ///   - cornerRadius: Notch only: the expanded panel's bottom corner radius (user setting).
    ///     Compact keeps the same proportion to its default.
    ///   - topCurve: Notch only: the expanded panel's concave ear radius (user setting). Compact
    ///     keeps the same proportion to its default.
    static func make(
        state: NotchState,
        geometry: NotchGeometry,
        sideWidth: CGFloat = Metrics.compactSideWidth,
        expandedWidth: CGFloat = Metrics.expandedWidth,
        belowHeight: CGFloat = 0,
        cornerRadius: CGFloat = Metrics.Notch.expandedBottomRadius,
        topCurve: CGFloat = Metrics.Notch.expandedTopRadius
    ) -> NotchLayout {
        let sideWidth = min(max(sideWidth, 0), Metrics.maxCompactSideWidth)
        let expandedWidth = min(max(expandedWidth, Metrics.expandedWidthRange.lowerBound), Metrics.expandedWidthRange.upperBound)
        let corners = NotchCorners(
            bottom: min(max(cornerRadius, Metrics.Notch.cornerRadiusRange.lowerBound), Metrics.Notch.cornerRadiusRange.upperBound),
            top: min(max(topCurve, Metrics.Notch.topCurveRange.lowerBound), Metrics.Notch.topCurveRange.upperBound)
        )
        var layout = switch geometry.style {
        case .notch: notchLayout(state: state, geometry: geometry, sideWidth: sideWidth, expandedWidth: expandedWidth, corners: corners)
        case .island: islandLayout(state: state, geometry: geometry, sideWidth: sideWidth, expandedWidth: expandedWidth)
        }
        if state == .compact && belowHeight > 0 {
            // The row takes the lip's place: its own height already clears the notch.
            layout.size.height = layout.headerHeight + belowHeight
            layout.bottomLip = 0
            // A taller island stays a pill; the notch keeps its corner radius.
            if geometry.style == .island { layout.bottomRadius = min(layout.size.height / 2, Metrics.Island.compactHeight * 0.75) }
        }
        return layout
    }

    /// The expanded radii the user picked; compact scales them by its defaults' ratio.
    private struct NotchCorners {
        var bottom: CGFloat
        var top: CGFloat

        var compactBottom: CGFloat { bottom * Metrics.Notch.compactBottomRadius / Metrics.Notch.expandedBottomRadius }
        var compactTop: CGFloat { top * Metrics.Notch.compactTopRadius / Metrics.Notch.expandedTopRadius }
    }

    private static func notchLayout(state: NotchState, geometry: NotchGeometry, sideWidth: CGFloat, expandedWidth: CGFloat, corners: NotchCorners) -> NotchLayout {
        let notch = geometry.idleSize
        switch state {
        case .idle:
            return NotchLayout(
                size: CGSize(width: notch.width - Metrics.Notch.idleWidthInset, height: notch.height - Metrics.Notch.idleHeightInset),
                topInset: 0, topRadius: 0, bottomRadius: Metrics.Notch.idleBottomRadius,
                horizontalInset: 0, centerGap: notch.width, headerHeight: notch.height, shadowPadding: 0
            )
        case .compact:
            let ears = corners.compactTop
            let lip = Metrics.Notch.compactBottomLip
            return NotchLayout(
                size: CGSize(width: notch.width + 2 * sideWidth + 2 * ears, height: notch.height + lip),
                topInset: 0, topRadius: ears, bottomRadius: corners.compactBottom,
                horizontalInset: ears, centerGap: notch.width, headerHeight: notch.height, shadowPadding: 0,
                bottomLip: lip
            )
        case .expanded:
            let ears = corners.top
            let minimumWidth = notch.width + 2 * sideWidth + 2 * ears
            return NotchLayout(
                size: CGSize(width: max(expandedWidth, minimumWidth), height: notch.height + Metrics.expandedContentHeight),
                topInset: 0, topRadius: ears, bottomRadius: corners.bottom,
                horizontalInset: ears, centerGap: notch.width, headerHeight: notch.height, shadowPadding: 0
            )
        }
    }

    private static func islandLayout(state: NotchState, geometry: NotchGeometry, sideWidth: CGFloat, expandedWidth: CGFloat) -> NotchLayout {
        let idle = geometry.idleSize
        switch state {
        case .idle:
            return NotchLayout(
                size: idle,
                // Vertically centered in the menu bar, like a menu bar item.
                topInset: max((geometry.menuBarHeight - idle.height) / 2, 0),
                topRadius: 0, bottomRadius: idle.height / 2,
                horizontalInset: 0, centerGap: 0, headerHeight: idle.height, shadowPadding: 0
            )
        case .compact:
            // Like the notch: the slots flank the resting capsule, so compact is idle width + two slots.
            let height = Metrics.Island.compactHeight
            let padding = Metrics.Island.horizontalPadding
            let gap = idle.width - 2 * padding
            return NotchLayout(
                size: CGSize(width: idle.width + 2 * sideWidth, height: height),
                topInset: Metrics.Island.compactTopInset,
                topRadius: 0, bottomRadius: height / 2,
                horizontalInset: padding, centerGap: gap, headerHeight: height, shadowPadding: 0
            )
        case .expanded:
            let header = Metrics.Island.expandedHeaderHeight
            return NotchLayout(
                size: CGSize(width: expandedWidth, height: header + Metrics.expandedContentHeight),
                topInset: Metrics.Island.expandedTopInset,
                topRadius: 0, bottomRadius: Metrics.Island.expandedCornerRadius,
                horizontalInset: Metrics.Island.horizontalPadding * 2, centerGap: 0,
                headerHeight: header, shadowPadding: Metrics.Island.shadowPadding
            )
        }
    }

    /// The shape's interactive area in global AppKit coordinates. It reaches up to (and 1 pt past) the
    /// screen's top edge, where `NSEvent.mouseLocation` sits when the cursor is pushed into the notch,
    /// and covers the island's small gap above the capsule. In notch style it never shrinks below the
    /// physical notch, even though the resting shape hides inside it.
    func hitRect(in geometry: NotchGeometry) -> CGRect {
        let minimum = geometry.style == .notch ? geometry.idleSize : .zero
        let width = max(size.width, minimum.width)
        let height = max(size.height, minimum.height)
        let bottom = geometry.screenFrame.maxY - topInset - height
        return CGRect(
            x: geometry.centerX - width / 2,
            y: bottom,
            width: width,
            height: geometry.screenFrame.maxY - bottom + 1
        )
    }

    /// The fixed panel frame for a display: top-anchored, centered on the notch, and big enough for
    /// the largest state (with its shadow) plus room for spring overshoot.
    static func panelFrame(in geometry: NotchGeometry) -> CGRect {
        // Sized for the widest settings allowed (the top curve widens the notch), so changing them
        // never resizes the panel.
        let side = Metrics.maxCompactSideWidth
        let widest = Metrics.expandedWidthRange.upperBound
        let ears = Metrics.Notch.topCurveRange.upperBound
        let expanded = make(state: .expanded, geometry: geometry, sideWidth: side, expandedWidth: widest, topCurve: ears)
        let compact = make(state: .compact, geometry: geometry, sideWidth: side, expandedWidth: widest, topCurve: ears)
        let contentWidth = max(expanded.size.width + 2 * expanded.shadowPadding, compact.size.width)
        let contentHeight = max(
            expanded.topInset + expanded.size.height + expanded.shadowPadding,
            compact.topInset + compact.size.height
        )
        // Even widths keep the shape exactly centered on the notch.
        let width = ((contentWidth + 2 * Metrics.panelMargin) / 2).rounded(.up) * 2
        let height = (contentHeight + Metrics.panelMargin).rounded(.up)
        return CGRect(
            x: geometry.centerX - width / 2,
            y: geometry.screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
