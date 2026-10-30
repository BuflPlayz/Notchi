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

    /// - Parameters:
    ///   - sideWidth: Width of each compact slot (user setting, or a module's own request).
    ///   - expandedWidth: Width of the expanded panel (user setting).
    static func make(
        state: NotchState,
        geometry: NotchGeometry,
        sideWidth: CGFloat = Metrics.compactSideWidth,
        expandedWidth: CGFloat = Metrics.expandedWidth
    ) -> NotchLayout {
        let sideWidth = min(max(sideWidth, 0), Metrics.maxCompactSideWidth)
        let expandedWidth = min(max(expandedWidth, Metrics.expandedWidthRange.lowerBound), Metrics.expandedWidthRange.upperBound)
        switch geometry.style {
        case .notch:
            return notchLayout(state: state, geometry: geometry, sideWidth: sideWidth, expandedWidth: expandedWidth)
        case .island:
            return islandLayout(state: state, geometry: geometry, sideWidth: sideWidth, expandedWidth: expandedWidth)
        }
    }

    private static func notchLayout(state: NotchState, geometry: NotchGeometry, sideWidth: CGFloat, expandedWidth: CGFloat) -> NotchLayout {
        let notch = geometry.idleSize
        switch state {
        case .idle:
            return NotchLayout(
                size: CGSize(width: notch.width - Metrics.Notch.idleWidthInset, height: notch.height - Metrics.Notch.idleHeightInset),
                topInset: 0, topRadius: 0, bottomRadius: Metrics.Notch.idleBottomRadius,
                horizontalInset: 0, centerGap: notch.width, headerHeight: notch.height, shadowPadding: 0
            )
        case .compact:
            let ears = Metrics.Notch.compactTopRadius
            return NotchLayout(
                size: CGSize(width: notch.width + 2 * sideWidth + 2 * ears, height: notch.height),
                topInset: 0, topRadius: ears, bottomRadius: Metrics.Notch.compactBottomRadius,
                horizontalInset: ears, centerGap: notch.width, headerHeight: notch.height, shadowPadding: 0
            )
        case .expanded:
            let ears = Metrics.Notch.expandedTopRadius
            let minimumWidth = notch.width + 2 * sideWidth + 2 * ears
            return NotchLayout(
                size: CGSize(width: max(expandedWidth, minimumWidth), height: notch.height + Metrics.expandedContentHeight),
                topInset: 0, topRadius: ears, bottomRadius: Metrics.Notch.expandedBottomRadius,
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
    /// and covers the island's small gap above the capsule.
    func hitRect(in geometry: NotchGeometry) -> CGRect {
        let bottom = geometry.screenFrame.maxY - topInset - size.height
        return CGRect(
            x: geometry.centerX - size.width / 2,
            y: bottom,
            width: size.width,
            height: geometry.screenFrame.maxY - bottom + 1
        )
    }

    /// The fixed panel frame for a display: top-anchored, centered on the notch, and big enough for
    /// the largest state (with its shadow) plus room for spring overshoot.
    static func panelFrame(in geometry: NotchGeometry) -> CGRect {
        // Sized for the widest settings allowed, so changing them never resizes the panel.
        let side = Metrics.maxCompactSideWidth
        let widest = Metrics.expandedWidthRange.upperBound
        let expanded = make(state: .expanded, geometry: geometry, sideWidth: side, expandedWidth: widest)
        let compact = make(state: .compact, geometry: geometry, sideWidth: side, expandedWidth: widest)
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
