import Foundation
import SwiftUI
import Testing
@testable import Notchi

struct FullScreenDetectionTests {
    /// Shape of `CGSCopyManagedDisplaySpaces`, as captured on macOS 27.2.
    private func displays(_ entries: [(id: String, currentType: Int)]) -> [[String: Any]] {
        entries.map { ["Display Identifier": $0.id, "Current Space": ["type": $0.currentType, "ManagedSpaceID": 1]] }
    }

    @Test func fullScreenSpaceOnThisDisplay() {
        let list = displays([("AAAA-1111", 4), ("BBBB-2222", 0)])
        #expect(FullScreenMonitor.isFullScreen(displays: list, displayUUID: "aaaa-1111"))   // UUID case doesn't matter
        #expect(!FullScreenMonitor.isFullScreen(displays: list, displayUUID: "BBBB-2222"))
    }

    @Test func sharedSpacesUseTheMainEntry() {
        // "Displays have separate Spaces" off: one entry called "Main".
        #expect(FullScreenMonitor.isFullScreen(displays: displays([("Main", 4)]), displayUUID: "ANY"))
        #expect(!FullScreenMonitor.isFullScreen(displays: displays([("Main", 0)]), displayUUID: "ANY"))
    }

    @Test func unknownShapesAreNotFullScreen() {
        #expect(!FullScreenMonitor.isFullScreen(displays: [], displayUUID: "X"))
        #expect(!FullScreenMonitor.isFullScreen(displays: [["Display Identifier": "X"]], displayUUID: "X"))
        #expect(!FullScreenMonitor.isFullScreen(displays: displays([("A", 4), ("B", 4)]), displayUUID: "C"))
    }
}

@MainActor
struct SuppressionTests {
    private func makeModel() -> (NotchViewModel, RecordingModule) {
        let registry = ModuleRegistry(defaults: UserDefaults(suiteName: "notchi.tests.\(UUID().uuidString)")!)
        let module = RecordingModule(id: "media")
        registry.register(module)
        return (NotchViewModel(geometry: .previewNotch, registry: registry), module)
    }

    @Test func fullScreenHidesOrdinaryActivities() async {
        let (model, module) = makeModel()
        module.liveActivity = LiveActivity(priority: .active)
        await Task.yield(); await Task.yield()
        #expect(model.state == .compact)

        model.setSuppressed(true)
        #expect(model.state == .idle)

        model.setSuppressed(false)
        #expect(model.state == .compact)
    }

    @Test func hudStillShowsInFullScreen() async {
        let (model, module) = makeModel()
        model.setSuppressed(true)
        module.liveActivity = LiveActivity(priority: .transient, showsInFullScreen: true)
        await Task.yield(); await Task.yield()
        #expect(model.state == .compact)
    }

    @Test func fullScreenIgnoresClicksAndCollapses() {
        let (model, _) = makeModel()
        model.expandNow()
        #expect(model.state == .expanded)

        model.setSuppressed(true)
        #expect(model.state == .idle)
        model.expandNow()
        #expect(model.state == .idle)
    }
}
