import ServiceManagement

/// Launch at login through `SMAppService.mainApp` (macOS 13+): no helper app, and it shows up in
/// System Settings › General › Login Items like any other app.
@MainActor
@Observable
final class LaunchAtLogin {
    static let shared = LaunchAtLogin()

    private(set) var status = SMAppService.mainApp.status
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled }
    /// The user turned it off in System Settings; only they can turn it back on there.
    var needsApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
