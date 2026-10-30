import AppKit

/// Borderless, transparent, non-activating panel that sits above the menu bar on every Space.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                       // SwiftUI draws its own shadow where needed
        isFloatingPanel = true                  // must come before `level`: setting it resets the level to .floating
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true           // clicks work without stealing focus from the frontmost app
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none               // no AppKit fade; SwiftUI owns all motion
    }

    override var canBecomeKey: Bool { true }    // so future text fields (timer input) can take focus
    override var canBecomeMain: Bool { false }

    /// AppKit normally pushes windows below the menu bar. The notch lives inside it, so keep the frame as-is.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
