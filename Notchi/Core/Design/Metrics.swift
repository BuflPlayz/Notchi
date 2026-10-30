import CoreGraphics

/// Every size and radius the notch surface uses, in points.
/// Kept in one place so the feel can be tuned without hunting through views.
enum Metrics {
    /// Default width of each compact slot (left and right of the notch): room for one glyph or artwork.
    static let compactSideWidth: CGFloat = 36
    /// Range of the "Live activity width" setting.
    static let compactSideWidthRange: ClosedRange<CGFloat> = 24...80
    /// Widest slot a module may ask for (for example, a timer readout). Sizes the fixed panel.
    static let maxCompactSideWidth: CGFloat = 120
    /// Default width of the expanded panel. It grows if the notch plus compact slots would be wider.
    static let expandedWidth: CGFloat = 460
    /// Range of the "Panel width" setting.
    static let expandedWidthRange: ClosedRange<CGFloat> = 380...600
    /// Height of the module area below the expanded panel's header band.
    static let expandedContentHeight: CGFloat = 140
    /// Room the fixed panel keeps beyond the largest shape, so spring overshoot never clips.
    static let panelMargin: CGFloat = 20

    /// Hardware-notch style (built-in MacBook display).
    enum Notch {
        /// At rest the shape hides just inside the physical notch, so its corners never peek out.
        static let idleWidthInset: CGFloat = 4
        static let idleHeightInset: CGFloat = 1
        static let idleBottomRadius: CGFloat = 12

        /// Concave "ears" where the surface meets the top bezel, and the rounded bottom corners.
        static let compactTopRadius: CGFloat = 6
        static let compactBottomRadius: CGFloat = 12
        static let expandedTopRadius: CGFloat = 14
        static let expandedBottomRadius: CGFloat = 32
    }

    /// Dynamic Island style (main display without a notch).
    enum Island {
        static let idleWidth: CGFloat = 120
        static let minIdleHeight: CGFloat = 18
        static let maxIdleHeight: CGFloat = 26
        /// Used when the menu bar is hidden, so its height can't be measured.
        static let fallbackMenuBarHeight: CGFloat = 24

        static let compactHeight: CGFloat = 32
        static let compactTopInset: CGFloat = 4
        static let horizontalPadding: CGFloat = 8

        static let expandedTopInset: CGFloat = 6
        static let expandedCornerRadius: CGFloat = 34
        static let expandedHeaderHeight: CGFloat = 38
        /// Room around the expanded card for its shadow.
        static let shadowPadding: CGFloat = 28
    }
}
