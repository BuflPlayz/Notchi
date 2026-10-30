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
    /// The module's page in the expanded panel.
    func expandedView() -> AnyView
    /// Optional pane for the Settings window.
    func settingsView() -> AnyView?

    /// Subscribe to system events. Called once after registration.
    func start()
    /// Tear down subscriptions (module disabled or app quitting).
    func stop()
}

extension NotchModule {
    func compactMinimal() -> AnyView { compactLeading() }
    func compactBelow() -> AnyView? { nil }
    func settingsView() -> AnyView? { nil }
    func start() {}
    func stop() {}
}
