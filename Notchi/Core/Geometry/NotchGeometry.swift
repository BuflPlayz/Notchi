import AppKit

/// Where the notch surface lives on a screen and which style it uses.
///
/// Built from `NSScreen` at runtime, or from raw values in tests and previews.
struct NotchGeometry: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        /// The surface grows out of the MacBook's camera housing.
        case notch
        /// No notch: a floating Dynamic Island capsule at top center.
        case island
    }

    var style: Style
    /// Screen frame in global AppKit coordinates (origin bottom-left).
    var screenFrame: CGRect
    /// Horizontal center of the notch or island, in global coordinates.
    var centerX: CGFloat
    /// The physical notch size, or the resting island capsule size.
    var idleSize: CGSize
    /// Height of the menu bar band on this screen.
    var menuBarHeight: CGFloat

    /// Pure constructor, so detection can be unit tested without a real screen.
    ///
    /// - Parameters:
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top`. Non-zero only on notched displays.
    ///   - topLeftArea: `NSScreen.auxiliaryTopLeftArea`, the menu bar area left of the notch.
    ///   - topRightArea: `NSScreen.auxiliaryTopRightArea`, the menu bar area right of the notch.
    ///   - menuBarHeight: Measured menu bar height; 0 when the menu bar is auto-hidden.
    ///   - forceIsland: Debug override that draws an island even on a notched display.
    static func make(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        topLeftArea: CGRect?,
        topRightArea: CGRect?,
        menuBarHeight: CGFloat,
        forceIsland: Bool = false
    ) -> NotchGeometry {
        if !forceIsland, safeAreaTop > 0, let left = topLeftArea, let right = topRightArea {
            // The notch is whatever the two auxiliary areas leave uncovered.
            let notchWidth = screenFrame.width - left.width - right.width
            if notchWidth > 0 {
                return NotchGeometry(
                    style: .notch,
                    screenFrame: screenFrame,
                    centerX: screenFrame.minX + left.width + notchWidth / 2,
                    idleSize: CGSize(width: notchWidth, height: safeAreaTop),
                    menuBarHeight: safeAreaTop
                )
            }
        }

        let barHeight = menuBarHeight > 0 ? menuBarHeight : Metrics.Island.fallbackMenuBarHeight
        let idleHeight = min(max(barHeight - 4, Metrics.Island.minIdleHeight), Metrics.Island.maxIdleHeight)
        return NotchGeometry(
            style: .island,
            screenFrame: screenFrame,
            centerX: screenFrame.midX,
            idleSize: CGSize(width: Metrics.Island.idleWidth, height: idleHeight),
            menuBarHeight: barHeight
        )
    }

    /// Reads notch and menu bar metrics from a live screen.
    @MainActor
    static func make(for screen: NSScreen, forceIsland: Bool) -> NotchGeometry {
        make(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            topLeftArea: screen.auxiliaryTopLeftArea,
            topRightArea: screen.auxiliaryTopRightArea,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
            forceIsland: forceIsland
        )
    }
}
