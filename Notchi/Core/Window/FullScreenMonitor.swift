import AppKit

/// Reports whether a display is currently showing a full-screen app.
///
/// macOS has no public API for this. `currentSystemPresentationOptions` only describes the
/// calling app, and a full-screen window's frame is identical to a zoomed one on a notched display.
/// What's reliable is the Space itself: the window server tags full-screen Spaces as type 4. It's
/// read through `CGSCopyManagedDisplaySpaces` (private, SIP-safe, used by window managers such as
/// yabai), loaded with `dlsym`, so if it ever disappears the monitor just reports "not full screen".
/// It's checked only when the active Space or the displays change, never polled.
@MainActor
final class FullScreenMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var isFullScreen = false

    /// The display to watch (the one the notch is on).
    var displayID: CGDirectDisplayID? {
        didSet { evaluate() }
    }

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private let mainConnectionID: MainConnectionID?
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpaces?
    private var observers: [NSObjectProtocol] = []

    /// The window server's Space type for full-screen apps.
    private nonisolated static let fullScreenSpaceType = 4

    init() {
        let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
        mainConnectionID = handle.flatMap { dlsym($0, "CGSMainConnectionID") }.map { unsafeBitCast($0, to: MainConnectionID.self) }
        copyManagedDisplaySpaces = handle.flatMap { dlsym($0, "CGSCopyManagedDisplaySpaces") }.map { unsafeBitCast($0, to: CopyManagedDisplaySpaces.self) }
    }

    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        })
        evaluate()
    }

    func stop() {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
        observers.removeAll()
    }

    private func evaluate() {
        let newValue = displayID.map(currentSpaceIsFullScreen) ?? false
        guard newValue != isFullScreen else { return }
        isFullScreen = newValue
        onChange?(newValue)
    }

    private func currentSpaceIsFullScreen(on displayID: CGDirectDisplayID) -> Bool {
        guard let mainConnectionID, let copyManagedDisplaySpaces,
              let displays = copyManagedDisplaySpaces(mainConnectionID())?.takeRetainedValue() as? [[String: Any]]
        else { return false }
        return Self.isFullScreen(displays: displays, displayUUID: Self.uuidString(for: displayID))
    }

    /// Picks the display's entry (or the single shared one when "Displays have separate Spaces"
    /// is off, where it's called "Main") and checks its current Space's type.
    nonisolated static func isFullScreen(displays: [[String: Any]], displayUUID: String?) -> Bool {
        let entry = displays.first { ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(displayUUID ?? "") == .orderedSame }
            ?? (displays.count == 1 ? displays.first : nil)
            ?? displays.first { $0["Display Identifier"] as? String == "Main" }
        let current = entry?["Current Space"] as? [String: Any]
        return (current?["type"] as? Int) == fullScreenSpaceType
    }

    private static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}

extension NSScreen {
    /// The Core Graphics display ID behind this screen.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
