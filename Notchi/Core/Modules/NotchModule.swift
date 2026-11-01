import SwiftUI

/// One feature living in the notch (media, timer, battery…).
///
/// The core only talks to modules through this protocol. To add a widget:
/// conform an `@Observable` class, then register it in `AppEnvironment`.
/// Changing `liveActivity` is enough to make the notch grow into compact mode.
@MainActor
protocol NotchModule: AnyObject, Observable {
    /// Stable identifier, also used for settings keys.
    var id: String { get }
    /// Name shown in the expanded header and in Settings.
    var title: String { get }
    /// SF Symbol for the expanded header's module switcher.
    var symbol: String { get }

    /// Non-nil while the module wants compact-mode space. Observed by the registry.
    var liveActivity: LiveActivity? { get }

    /// Content for the slot left of the notch.
    func compactLeading() -> AnyView
    /// Content for the slot right of the notch.
    func compactTrailing() -> AnyView
    /// One glyph for the round bubble beside the notch, shown while another activity has the
    /// middle. Defaults to `compactLeading()`.
    func compactMinimal() -> AnyView
    /// Full-width row below the notch in compact mode, shown when the live activity asks for
    /// `belowHeight`. Nil by default.
    func compactBelow() -> AnyView?
    /// Whether the module has a page (and a tab) in the expanded panel. True by default.
    var showsInPanel: Bool { get }
    /// The module's page in the expanded panel.
    func expandedView() -> AnyView
    /// Optional pane for the Settings window.
    func settingsView() -> AnyView?

    /// Subscribe to system events. Called once after registration.
    func start()
    /// Tear down subscriptions (module disabled or app quitting).
    func stop()
}

/// A module whose live activities come and go on their own, one per thing it follows (each running
/// coding agent, say). To compact mode every child is a module of its own: it takes the middle or a
/// bubble and can be swapped in. Settings, the panel's tabs and the module order only see the group.
@MainActor
protocol NotchActivityGroup: NotchModule {
    /// The group's children, in tie-break order. Ids must be unique across all modules. Keep a child
    /// listed for a moment after its activity ends, so the notch can animate its content away.
    var activities: [any NotchModule] { get }
}

/// A module that takes things dragged onto the notch. While a drag is over the open notch, the
/// panel shows its `dropView()` in place of the selected page.
@MainActor
protocol NotchDropHandler: NotchModule {
    /// Drop targets for the expanded panel, shown only while something is being dragged.
    func dropView() -> AnyView
}

extension EnvironmentValues {
    /// Called by a drop view once it has taken a drop, so the panel leaves drop mode right away.
    @Entry var notchDropFinished: @MainActor () -> Void = {}
}

extension NotchModule {
    var showsInPanel: Bool { true }
    func compactMinimal() -> AnyView { compactLeading() }
    func compactBelow() -> AnyView? { nil }
    func settingsView() -> AnyView? { nil }
    func start() {}
    func stop() {}
}
