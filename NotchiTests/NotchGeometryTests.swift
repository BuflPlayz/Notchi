import CoreGraphics
import Testing
@testable import Notchi

struct NotchGeometryTests {
    @Test func detectsHardwareNotchFromAuxiliaryAreas() {
        let geometry = NotchGeometry.previewNotch

        #expect(geometry.style == .notch)
        #expect(geometry.idleSize == CGSize(width: 188, height: 32))
        #expect(geometry.centerX == 756)
        #expect(geometry.menuBarHeight == 32)
    }

    @Test func notchOnSecondaryScreenUsesGlobalCoordinates() {
        let geometry = NotchGeometry.make(
            screenFrame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
            safeAreaTop: 32,
            topLeftArea: CGRect(x: 0, y: 950, width: 662, height: 32),
            topRightArea: CGRect(x: 850, y: 950, width: 662, height: 32),
            menuBarHeight: 32
        )
        #expect(geometry.centerX == -756)
    }

    @Test func screenWithoutNotchBecomesIsland() {
        let geometry = NotchGeometry.previewIsland

        #expect(geometry.style == .island)
        #expect(geometry.centerX == 1280)
        #expect(geometry.idleSize == CGSize(width: Metrics.Island.idleWidth, height: 20))
    }

    @Test func forceIslandOverridesNotch() {
        let geometry = NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 32,
            topLeftArea: CGRect(x: 0, y: 950, width: 662, height: 32),
            topRightArea: CGRect(x: 850, y: 950, width: 662, height: 32),
            menuBarHeight: 37,
            forceIsland: true
        )
        #expect(geometry.style == .island)
        #expect(geometry.idleSize.height == Metrics.Island.maxIdleHeight)
    }

    @Test func hiddenMenuBarFallsBackToDefaultHeight() {
        let geometry = NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            safeAreaTop: 0, topLeftArea: nil, topRightArea: nil,
            menuBarHeight: 0
        )
        #expect(geometry.menuBarHeight == Metrics.Island.fallbackMenuBarHeight)
    }
}
