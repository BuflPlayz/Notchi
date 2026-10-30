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
            #expect(hit.width == layout.size.width)
            #expect(hit.maxY > geometry.screenFrame.maxY)
            #expect(hit.minY == geometry.screenFrame.maxY - layout.topInset - layout.size.height)
        }
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
}
