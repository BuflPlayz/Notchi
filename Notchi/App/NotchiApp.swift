import SwiftUI

/// Notchi has no main window, Dock icon or menu bar item (`LSUIElement`).
/// The notch panel is created by `AppDelegate`; the only SwiftUI scene is Settings.
@main
struct NotchiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(registry: appDelegate.environment.registry)
        }
    }
}
