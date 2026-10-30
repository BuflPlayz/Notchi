import CoreGraphics

/// Every size and radius the notch surface uses, in points.
/// Kept in one place so the feel can be tuned without hunting through views.
enum Metrics {
    /// Gap between the surface's sides and compact content pinned to the edges: about the space
    /// above and below a compact glyph, so the padding looks even all round.
    static let compactEdgeInset: CGFloat = 5
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
    /// Room the fixed panel keeps beyond the largest shape, so spring overshoot never clips
    /// (up to the bounciest "Open animation" setting). Clicks only land on the shape itself.
    static let panelMargin: CGFloat = 48

    /// Hardware-notch style (built-in MacBook display).
    enum Notch {
        /// At rest the shape hides just inside the physical notch, so its corners never peek out.
        /// Its outline fades away as it gets there (see `NotchContainerView`).
        static let idleWidthInset: CGFloat = 4
        static let idleHeightInset: CGFloat = 1
        static let idleBottomRadius: CGFloat = 12

        /// Concave "ears" where the surface meets the top bezel, and the rounded bottom corners.
        static let compactTopRadius: CGFloat = 6
        static let compactBottomRadius: CGFloat = 12
        /// How far the compact surface reaches below the physical notch, so its bottom edge and
        /// outline show instead of hiding under the hardware.
        static let compactBottomLip: CGFloat = 4
        static let expandedTopRadius: CGFloat = 14
        static let expandedBottomRadius: CGFloat = 32

        /// Bottom corner radius of the physical notch, roughly.
        static let hardwareBottomRadius: CGFloat = 8
        /// Default for how far the hardware notch's black feathers out into the glass.
        static let hardwareBlend: CGFloat = 16
        /// Range of the "Notch blend" setting.
        static let hardwareBlendRange: ClosedRange<CGFloat> = 0...60
        /// The opened notch is about five times taller than the closed one, so its fade runs longer
        /// to look the same.
        static let expandedBlendScale: CGFloat = 3

        /// Range of the "Corner radius" setting, which sets `expandedBottomRadius` (compact scales along).
        static let cornerRadiusRange: ClosedRange<CGFloat> = 0...48
        /// Range of the "Top curve" setting, which sets `expandedTopRadius` (compact scales along).
        static let topCurveRange: ClosedRange<CGFloat> = 0...28
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
