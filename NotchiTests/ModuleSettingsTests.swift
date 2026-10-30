import Foundation
import SwiftUI
import Testing
@testable import Notchi

@MainActor
struct ModuleSettingsTests {
    /// A fresh, private defaults suite per test, so tests never touch the real settings.
    private func makeRegistry(_ ids: [String] = ["clock", "media", "system"]) -> (ModuleRegistry, [RecordingModule]) {
        let defaults = UserDefaults(suiteName: "notchi.tests.\(UUID().uuidString)")!
        let registry = ModuleRegistry(defaults: defaults)
        let modules = ids.map(RecordingModule.init)
        modules.forEach(registry.register)
        return (registry, modules)
    }

    @Test func defaultOrderIsRegistrationOrder() {
        let (registry, _) = makeRegistry()
        #expect(registry.modules.map(\.id) == ["clock", "media", "system"])
        #expect(registry.orderedModules.map(\.id) == ["clock", "media", "system"])
    }

    @Test func reorderingChangesTabsAndTieBreaks() {
        let (registry, modules) = makeRegistry()
        modules[0].liveActivity = LiveActivity(priority: .active)    // clock
        modules[1].liveActivity = LiveActivity(priority: .active)    // media
        #expect(registry.foreground?.id == "clock")

        registry.move(fromOffsets: IndexSet(integer: 1), toOffset: 0) // media first
        #expect(registry.modules.map(\.id) == ["media", "clock", "system"])
        #expect(registry.foreground?.id == "media")
    }

    @Test func disablingStopsAndHidesAModule() {
        let (registry, modules) = makeRegistry()
        registry.startAll()
        #expect(modules[1].startCount == 1)

        modules[1].liveActivity = LiveActivity(priority: .urgent)
        registry.setEnabled(false, for: "media")
        #expect(registry.modules.map(\.id) == ["clock", "system"])
        #expect(registry.module(withID: "media") == nil)
        #expect(registry.foreground == nil)                            // its activity no longer counts
        #expect(modules[1].stopCount == 1)
        #expect(registry.orderedModules.count == 3)                    // still listed in Settings

        registry.setEnabled(true, for: "media")
        #expect(modules[1].startCount == 2)
        #expect(registry.modules.map(\.id) == ["clock", "media", "system"])  // keeps its place
    }

    @Test func lastModuleCantBeDisabled() {
        let (registry, _) = makeRegistry(["clock", "media"])
        registry.setEnabled(false, for: "clock")
        registry.setEnabled(false, for: "media")
        #expect(registry.modules.map(\.id) == ["media"])
    }

    @Test func newModulesAppendAfterSavedOrder() {
        let defaults = UserDefaults(suiteName: "notchi.tests.\(UUID().uuidString)")!
        defaults.set(["media", "clock"], forKey: ModuleRegistry.orderKey)
        let registry = ModuleRegistry(defaults: defaults)
        ["clock", "system", "media"].map(RecordingModule.init).forEach(registry.register)
        #expect(registry.modules.map(\.id) == ["media", "clock", "system"])
    }

    @Test func resetRestoresDefaults() {
        let (registry, _) = makeRegistry()
        registry.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        registry.setEnabled(false, for: "clock")
        registry.resetModules()
        #expect(registry.modules.map(\.id) == ["clock", "media", "system"])
    }
}

/// Counts start/stop calls.
@MainActor
@Observable
final class RecordingModule: NotchModule {
    let id: String
    let title: String
    let symbol = "circle"
    var liveActivity: LiveActivity?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(id: String) {
        self.id = id
        self.title = id.capitalized
    }

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}
