import CoreGraphics
import Testing
@testable import Notchi

struct NotchLayoutTests {
    @Test(arguments: [NotchGeometry.previewNotch, NotchGeometry.previewIsland])
    func statesGrowMonotonically(geometry: NotchGeometry) {
        let idle = NotchLayout.make(state: .idle, geometry: geometry)
        let compact = NotchLayout.make(state: .compact, geometry: geometry)
        let expanded = NotchLayout.make(state: .expanded, geometry: geometry)

        #expect(idle.size.width < compact.size.width)
        #expect(compact.size.width < expanded.size.width)
        #expect(idle.size.height <= compact.size.height)
        #expect(compact.size.height < expanded.size.height)
    }

    @Test func idleNotchHidesInsideHardwareNotch() {
        let geometry = NotchGeometry.previewNotch
        let idle = NotchLayout.make(state: .idle, geometry: geometry)

        #expect(idle.size.width < geometry.idleSize.width)
        #expect(idle.size.height < geometry.idleSize.height)
        #expect(idle.topRadius == 0)
    }

    @Test func compactNotchKeepsSlotsClearOfTheNotch() {
        let geometry = NotchGeometry.previewNotch
        let compact = NotchLayout.make(state: .compact, geometry: geometry, sideWidth: 80)

        #expect(compact.centerGap == geometry.idleSize.width)
        #expect(compact.size.width == geometry.idleSize.width + 2 * 80 + 2 * compact.topRadius)
    }

    @Test func compactNotchReachesBelowTheHardware() {
        let geometry = NotchGeometry.previewNotch
        let compact = NotchLayout.make(state: .compact, geometry: geometry)

        #expect(compact.headerHeight == geometry.idleSize.height)          // slots stay level with the menu bar
        #expect(compact.size.height == geometry.idleSize.height + Metrics.Notch.compactBottomLip)
    }

    @Test func cornerSettingsShapeTheNotchAndCompactScalesAlong() {
        let geometry = NotchGeometry.previewNotch
        let expanded = NotchLayout.make(state: .expanded, geometry: geometry, cornerRadius: 16, topCurve: 28)
        let compact = NotchLayout.make(state: .compact, geometry: geometry, cornerRadius: 16, topCurve: 28)

        #expect(expanded.bottomRadius == 16)
        #expect(expanded.topRadius == 28)
        #expect(compact.bottomRadius == 16 * Metrics.Notch.compactBottomRadius / Metrics.Notch.expandedBottomRadius)
        #expect(compact.topRadius == 28 * Metrics.Notch.compactTopRadius / Metrics.Notch.expandedTopRadius)
        // The ears sit outside the slots, so a bigger curve widens the compact notch.
        #expect(compact.size.width > NotchLayout.make(state: .compact, geometry: geometry).size.width)
        // Out-of-range values are clamped.
        #expect(NotchLayout.make(state: .expanded, geometry: geometry, cornerRadius: 500).bottomRadius == Metrics.Notch.cornerRadiusRange.upperBound)
    }

    @Test func idleIslandIsCenteredInMenuBar() {
        let geometry = NotchGeometry.previewIsland
        let idle = NotchLayout.make(state: .idle, geometry: geometry)

        #expect(idle.topInset * 2 + idle.size.height == geometry.menuBarHeight)
        #expect(idle.bottomRadius == idle.size.height / 2)
    }

    @Test(arguments: [NotchState.idle, .compact, .expanded])
    func hitRectMatchesShapeAndReachesTopEdge(state: NotchState) {
        for geometry in [NotchGeometry.previewNotch, .previewIsland] {
            let layout = NotchLayout.make(state: state, geometry: geometry)
            let hit = layout.hitRect(in: geometry)

            #expect(hit.midX == geometry.centerX)
            #expect(hit.width == (geometry.style == .notch ? max(layout.size.width, geometry.idleSize.width) : layout.size.width))
            #expect(hit.maxY > geometry.screenFrame.maxY)
            // The notch's resting shape hides up inside the hardware; hovering still covers all of it.
            let height = geometry.style == .notch ? max(layout.size.height, geometry.idleSize.height) : layout.size.height
            #expect(hit.minY == geometry.screenFrame.maxY - layout.topInset - height)
        }
    }

    @Test func restingNotchHidesInsideTheHardware() {
        let geometry = NotchGeometry.previewNotch
        let idle = NotchLayout.make(state: .idle, geometry: geometry)

        #expect(idle.size.height < geometry.idleSize.height)
        #expect(idle.size.width < geometry.idleSize.width)
        let hit = idle.hitRect(in: geometry)
        #expect(hit.minY == geometry.screenFrame.maxY - geometry.idleSize.height)
        #expect(hit.width == geometry.idleSize.width)
    }

    @Test func panelHoldsEveryStateWithRoomToOvershoot() {
        for geometry in [NotchGeometry.previewNotch, .previewIsland] {
            let panel = NotchLayout.panelFrame(in: geometry)
            #expect(panel.maxY == geometry.screenFrame.maxY)
            #expect(panel.midX == geometry.centerX)

            for state in [NotchState.idle, .compact, .expanded] {
                for side in [Metrics.compactSideWidth, Metrics.maxCompactSideWidth, 500] {
                    let shape = NotchLayout.make(state: state, geometry: geometry, sideWidth: side).hitRect(in: geometry)
                    let shapeBelowTop = CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: geometry.screenFrame.maxY - shape.minY)
                    #expect(panel.insetBy(dx: Metrics.panelMargin, dy: 0).contains(shapeBelowTop))
                    #expect(shape.minY - panel.minY >= Metrics.panelMargin)
                }
            }
        }
    }

    @Test func compactIsNarrow() {
        let notch = NotchLayout.make(state: .compact, geometry: .previewNotch)
        #expect(notch.size.width - NotchGeometry.previewNotch.idleSize.width <= 2 * 36 + 2 * notch.topRadius)
        let island = NotchLayout.make(state: .compact, geometry: .previewIsland)
        #expect(island.size.width == Metrics.Island.idleWidth + 2 * Metrics.compactSideWidth)
    }

    @Test func expandedIslandReservesRoomForShadow() {
        let layout = NotchLayout.make(state: .expanded, geometry: .previewIsland)
        #expect(layout.shadowPadding > 0)
        #expect(NotchLayout.make(state: .expanded, geometry: .previewNotch).shadowPadding == 0)
    }

    @Test(arguments: [NotchGeometry.previewNotch, NotchGeometry.previewIsland])
    func rowBelowTheNotchGrowsCompactOnly(geometry: NotchGeometry) {
        let plain = NotchLayout.make(state: .compact, geometry: geometry)
        let withRow = NotchLayout.make(state: .compact, geometry: geometry, belowHeight: 18)

        #expect(withRow.size.height == plain.headerHeight + 18)             // the row replaces the notch's lip
        #expect(withRow.headerHeight == plain.headerHeight)              // the side row keeps its height
        #expect(withRow.size.width == plain.size.width)
        #expect(NotchLayout.make(state: .expanded, geometry: geometry, belowHeight: 18) == NotchLayout.make(state: .expanded, geometry: geometry))
        // Still fits inside the fixed panel.
        let panel = NotchLayout.panelFrame(in: geometry)
        #expect(withRow.hitRect(in: geometry).minY - panel.minY >= Metrics.panelMargin)
    }
}

struct PanelTabTests {
    /// Tabs that don't fit left of the notch go right of it instead of under the camera.
    @Test func tabsSplitAroundTheNotch() {
        #expect(ExpandedContentView.tabsFitting(sideWidth: 114) == 3)   // 3 × 26 + 2 × 4 = 86; a fourth needs 116
        #expect(ExpandedContentView.tabsFitting(sideWidth: 146) == 5)
        #expect(ExpandedContentView.tabsFitting(sideWidth: 0) == 1)
    }
}
