import CoreGraphics
import Testing
@testable import Notchi

struct SatelliteSwipeTests {
    @Test func swipesPointAtTheSideTheyMoveToward() {
        #expect(SatelliteSwipe.side(translation: CGSize(width: 40, height: 3), predictedEnd: CGSize(width: 40, height: 3)) == .trailing)
        #expect(SatelliteSwipe.side(translation: CGSize(width: -40, height: -3), predictedEnd: CGSize(width: -40, height: -3)) == .leading)
    }

    @Test func shortOrVerticalMovesAreNotSwipes() {
        // Too short, and not flicked.
        #expect(SatelliteSwipe.side(translation: CGSize(width: 12, height: 0), predictedEnd: CGSize(width: 14, height: 0)) == nil)
        // Mostly down, however far.
        #expect(SatelliteSwipe.side(translation: CGSize(width: 30, height: 50), predictedEnd: CGSize(width: 30, height: 80)) == nil)
    }

    @Test func aQuickFlickCountsBeforeTheFullDistance() {
        #expect(SatelliteSwipe.side(translation: CGSize(width: 10, height: 1), predictedEnd: CGSize(width: 90, height: 2)) == .trailing)
        // A flick back the other way doesn't point where the pointer went.
        #expect(SatelliteSwipe.side(translation: CGSize(width: 10, height: 1), predictedEnd: CGSize(width: -90, height: 2)) == nil)
    }

    @Test func barelyMovingIsAClick() {
        #expect(SatelliteSwipe.isClick(CGSize(width: 2, height: 2)))
        #expect(!SatelliteSwipe.isClick(CGSize(width: 6, height: 0)))
    }

    @Test func theLeanFollowsButStaysSmall() {
        #expect(SatelliteSwipe.lean(for: 0, hasTarget: true) == 0)
        #expect(SatelliteSwipe.lean(for: 500, hasTarget: true) <= SatelliteSwipe.maxLean)
        #expect(SatelliteSwipe.lean(for: -500, hasTarget: true) >= -SatelliteSwipe.maxLean)
        #expect(abs(SatelliteSwipe.lean(for: 40, hasTarget: false)) < SatelliteSwipe.lean(for: 40, hasTarget: true))
    }
}
