import AppKit

/// Hover detection and click-through for the notch panel.
///
/// The panel is large and never resizes, so animations can't shift. Only the visible shape should
/// be interactive, though. Mouse-moved monitors compare the cursor with the shape's current frame.
/// Inside, the panel takes mouse events. Outside, it ignores them, so they fall through to whatever
/// is underneath. Monitors only fire while the mouse moves, so this costs nothing at rest.
@MainActor
final class HoverController {
    /// Reports cursor enter/exit over the shape.
    var onHoverChange: ((Bool) -> Void)?

    private let panel: NSPanel
    private var hitRect: CGRect = .zero
    private var isInside = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(panel: NSPanel) {
        self.panel = panel
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
    }

    func start() {
        // Global monitors see events going to other apps (no Accessibility needed for mouse events);
        // the local one sees events going to the panel itself.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(cursorMoved: true) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.update(cursorMoved: true) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    /// Sets the interactive area (screen coordinates) to the shape's new target frame.
    func setHitRect(_ rect: CGRect) {
        hitRect = rect
        update(cursorMoved: false)
    }

    private func update(cursorMoved: Bool) {
        let inside = hitRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        guard inside != isInside else { return }
        // A shape that grows under a resting cursor (a live activity appearing) shouldn't count as
        // a hover. Entering requires real movement; leaving is reported either way.
        if inside && !cursorMoved { return }
        isInside = inside
        onHoverChange?(inside)
    }
}
