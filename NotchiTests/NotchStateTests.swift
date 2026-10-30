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
