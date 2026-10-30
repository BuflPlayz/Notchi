import SwiftUI
import Testing
@testable import Notchi

struct NotchStateTests {
    @Test func resolveTable() {
        #expect(NotchState.resolve(expandRequested: false, hasLiveActivity: false) == .idle)
        #expect(NotchState.resolve(expandRequested: false, hasLiveActivity: true) == .compact)
        #expect(NotchState.resolve(expandRequested: true, hasLiveActivity: false) == .expanded)
        #expect(NotchState.resolve(expandRequested: true, hasLiveActivity: true) == .expanded)
    }
}

@MainActor
struct ModuleRegistryTests {
    @Test func highestPriorityWins() {
        let registry = ModuleRegistry(defaults: UserDefaults(suiteName: "notchi.tests.\(UUID().uuidString)")!)
        let media = TestModule(id: "media", priority: .active)
        let battery = TestModule(id: "battery", priority: .transient)
        registry.register(media)
        registry.register(battery)

        #expect(registry.foreground?.id == "battery")
        #expect(registry.background.map(\.id) == ["media"])

        battery.liveActivity = nil
        #expect(registry.foreground?.id == "media")
        #expect(registry.background.isEmpty)
    }

    @Test func tiesGoToFirstRegistered() {
        let registry = ModuleRegistry(defaults: UserDefaults(suiteName: "notchi.tests.\(UUID().uuidString)")!)
        registry.register(TestModule(id: "a", priority: .active))
        registry.register(TestModule(id: "b", priority: .active))
        #expect(registry.foreground?.id == "a")
    }

    @Test func duplicateIDsAreIgnored() {
        let registry = ModuleRegistry(defaults: UserDefaults(suiteName: "notchi.tests.\(UUID().uuidString)")!)
        registry.register(TestModule(id: "a", priority: nil))
        registry.register(TestModule(id: "a", priority: .urgent))
        #expect(registry.modules.count == 1)
        #expect(registry.foreground == nil)
    }

    @Test func viewModelFollowsLiveActivities() async {
        let registry = ModuleRegistry(defaults: UserDefaults(suiteName: "notchi.tests.\(UUID().uuidString)")!)
        let module = TestModule(id: "timer", priority: nil)
        registry.register(module)
        let model = NotchViewModel(geometry: .previewNotch, registry: registry)
        #expect(model.state == .idle)

        module.liveActivity = LiveActivity(priority: .active)
        await Task.yield()
        await Task.yield()
        #expect(model.state == .compact)

        model.expandNow()
        #expect(model.state == .expanded)

        model.collapse()
        #expect(model.state == .compact)
    }
}

struct SatelliteSlotsTests {
    @Test func loneBubbleGoesTrailingThenLeading() {
        let one = SatelliteSlots().reconciled(with: ["a"])
        #expect(one == SatelliteSlots(leading: nil, trailing: "a"))
        let two = one.reconciled(with: ["b", "a"])
        #expect(two == SatelliteSlots(leading: "b", trailing: "a"))
    }

    @Test func bubblesKeepTheirSides() {
        let slots = SatelliteSlots(leading: "a", trailing: "b")
        #expect(slots.reconciled(with: ["b"]) == SatelliteSlots(leading: nil, trailing: "b"))
        #expect(slots.reconciled(with: ["b", "a"]) == slots)
    }

    @Test func extraCandidatesDontShow() {
        let slots = SatelliteSlots().reconciled(with: ["a", "b", "c"])
        #expect(slots.occupied.count == 2)
        #expect(slots.side(of: "c") == nil)
    }
}

@MainActor
struct SatelliteTests {
    private func makeRegistry() -> ModuleRegistry {
        ModuleRegistry(defaults: UserDefaults(suiteName: "notchi.tests.\(UUID().uuidString)")!)
    }

    @Test func runnersUpBecomeCandidatesButToastsDont() {
        let registry = makeRegistry()
        registry.register(TestModule(id: "clock", priority: .active))
        registry.register(TestModule(id: "media", priority: .ambient))
        registry.register(TestModule(id: "system", priority: .transient))
        #expect(registry.foreground?.id == "system")
        #expect(registry.primary?.id == "clock")
        #expect(registry.satelliteCandidates.map(\.id) == ["media"])
    }

    @Test func preferredModuleKeepsTheMiddleUntilSomethingUrgent() {
        let registry = makeRegistry()
        let clock = TestModule(id: "clock", priority: .active)
        registry.register(clock)
        registry.register(TestModule(id: "media", priority: .ambient))
        registry.preferredID = "media"
        #expect(registry.primary?.id == "media")

        clock.liveActivity = LiveActivity(priority: .urgent)
        #expect(registry.primary?.id == "clock")
    }

    @Test func clickingABubbleSwapsItIntoTheMiddle() async {
        let registry = makeRegistry()
        let clock = TestModule(id: "clock", priority: .active)
        registry.register(clock)
        registry.register(TestModule(id: "media", priority: .active))
        let model = NotchViewModel(geometry: .previewNotch, registry: registry)
        #expect(model.state == .compact)
        #expect(registry.foreground?.id == "clock")
        #expect(model.visibleSatellites.map(\.module.id) == ["media"])
        #expect(model.satellites.trailing == "media")

        model.bringToFront("media")
        #expect(registry.foreground?.id == "media")
        #expect(model.swapCount == 1)
        // The clicked bubble merges in first; the replaced activity squeezes out into its slot a beat later.
        #expect(model.satellites.trailing == nil)
        try? await Task.sleep(for: Motion.swapBeat * 3)
        #expect(model.satellites.trailing == "clock")

        // The pick ends with its activity, and the bubble merges back into the middle.
        (registry.module(withID: "media") as? TestModule)?.liveActivity = nil
        await Task.yield()
        await Task.yield()
        #expect(registry.preferredID == nil)
        #expect(registry.foreground?.id == "clock")
        #expect(model.visibleSatellites.isEmpty)
    }

    @Test func bubblesHideWhileExpanded() {
        let registry = makeRegistry()
        registry.register(TestModule(id: "clock", priority: .active))
        registry.register(TestModule(id: "media", priority: .active))
        let model = NotchViewModel(geometry: .previewIsland, registry: registry)
        model.expandNow()
        #expect(model.visibleSatellites.isEmpty)
        model.collapse()
        #expect(model.visibleSatellites.map(\.side) == [.trailing])
    }

    @Test func bubblesSitClearOfTheSurfaceInsideThePanel() {
        for geometry in [NotchGeometry.previewNotch, .previewIsland] {
            let layout = NotchLayout.make(state: .compact, geometry: geometry, sideWidth: Metrics.maxCompactSideWidth, topCurve: Metrics.Notch.topCurveRange.upperBound)
            let surface = layout.hitRect(in: geometry)
            let panel = NotchLayout.panelFrame(in: geometry)
            for side in SatelliteSide.allCases {
                let bubble = layout.satelliteHitRect(side, in: geometry)
                #expect(!bubble.intersects(surface))
                #expect(panel.contains(bubble))
                #expect(bubble.maxY <= geometry.screenFrame.maxY)
            }
        }
    }
}

@MainActor
@Observable
private final class TestModule: NotchModule {
    let id: String
    let title = "Test"
    let symbol = "circle"
    var liveActivity: LiveActivity?

    init(id: String, priority: LiveActivity.Priority?) {
        self.id = id
        self.liveActivity = priority.map { LiveActivity(priority: $0) }
    }

    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}
