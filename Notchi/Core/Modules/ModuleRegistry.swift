import Foundation
import Observation

/// Holds the registered modules, which of them are enabled and in what order, and decides which
/// one owns compact mode.
///
/// Order and enablement are user settings (Settings › Modules). The order sets the tabs in the
/// expanded panel and breaks priority ties in compact mode. Disabled modules are stopped, so they
/// cost nothing.
@MainActor
@Observable
final class ModuleRegistry {
    /// Every registered module, in registration (default) order.
    private(set) var allModules: [any NotchModule] = []
    /// Enabled modules in the user's order. This is what the notch uses.
    private(set) var modules: [any NotchModule] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isStarted = false

    static let orderKey = "moduleOrder"
    static let disabledKey = "disabledModules"

    /// - Parameter defaults: Where order and enablement are stored; tests pass a throwaway suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func register(_ module: any NotchModule) {
        guard !allModules.contains(where: { $0.id == module.id }) else { return }
        allModules.append(module)
        applyPreferences()
    }

    func module(withID id: String) -> (any NotchModule)? {
        modules.first { $0.id == id }
    }

    /// The module whose live activity fills the compact slots: highest priority wins,
    /// ties go to the earlier module. Reading this tracks every enabled module's activity.
    var foreground: (any NotchModule)? {
        var winner: (module: any NotchModule, priority: LiveActivity.Priority)?
        for module in modules {
            guard let priority = module.liveActivity?.priority else { continue }
            if winner == nil || priority > winner!.priority {
                winner = (module, priority)
            }
        }
        return winner?.module
    }

    /// Modules with a live activity that lost to `foreground`.
    var background: [any NotchModule] {
        let winnerID = foreground?.id
        return modules.filter { $0.liveActivity != nil && $0.id != winnerID }
    }

    func startAll() {
        isStarted = true
        modules.forEach { $0.start() }
    }

    func stopAll() {
        modules.forEach { $0.stop() }
        isStarted = false
    }

    // MARK: User settings

    /// All modules in the user's order, enabled or not, for the Settings list.
    var orderedModules: [any NotchModule] {
        let order = defaults.stringArray(forKey: Self.orderKey) ?? []
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return allModules.enumerated()
            .sorted { lhs, rhs in
                // Known ids by saved position; new modules keep registration order, after them.
                (rank[lhs.element.id] ?? order.count + lhs.offset, lhs.offset)
                    < (rank[rhs.element.id] ?? order.count + rhs.offset, rhs.offset)
            }
            .map(\.element)
    }

    func isEnabled(_ id: String) -> Bool {
        !(defaults.stringArray(forKey: Self.disabledKey) ?? []).contains(id)
    }

    /// Enables or disables a module. The last enabled module can't be disabled.
    func setEnabled(_ enabled: Bool, for id: String) {
        var disabled = Set(defaults.stringArray(forKey: Self.disabledKey) ?? [])
        if enabled {
            disabled.remove(id)
        } else {
            guard modules.count > 1 || !modules.contains(where: { $0.id == id }) else { return }
            disabled.insert(id)
        }
        defaults.set(disabled.sorted(), forKey: Self.disabledKey)
        applyPreferences()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = orderedModules.map(\.id)
        let moving = source.map { ids[$0] }
        let insertion = destination - source.filter { $0 < destination }.count
        ids.remove(atOffsets: source)
        ids.insert(contentsOf: moving, at: insertion)
        defaults.set(ids, forKey: Self.orderKey)
        applyPreferences()
    }

    func resetModules() {
        defaults.removeObject(forKey: Self.orderKey)
        defaults.removeObject(forKey: Self.disabledKey)
        applyPreferences()
    }

    /// Rebuilds `modules` from the saved order and enablement, starting and stopping modules
    /// that changed state.
    private func applyPreferences() {
        let previous = Set(modules.map(\.id))
        let updated = orderedModules.filter { isEnabled($0.id) }
        modules = updated
        guard isStarted else { return }
        let current = Set(updated.map(\.id))
        for module in allModules {
            if current.contains(module.id) && !previous.contains(module.id) { module.start() }
            if !current.contains(module.id) && previous.contains(module.id) { module.stop() }
        }
    }
}
