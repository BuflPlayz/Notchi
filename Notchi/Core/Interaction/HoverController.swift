import AppKit

/// Hover detection and click-through for the notch panel.
///
/// The panel is large and never resizes, so animations can't shift. Only the visible shape should
/// be interactive, though. Mouse-moved monitors compare the cursor with the shape's current frame.
/// Inside, the panel takes mouse events. Outside, it ignores them, so they fall through to whatever
/// is underneath. Monitors only fire while the mouse moves, so this costs nothing at rest.
///
/// Safe zones are the menu bar beside the notch that the compact shape covers. There the panel
/// never takes the mouse, even over the shape, and reports it, so the notch can step aside and
/// uncover the menu bar icons underneath.
@MainActor
final class HoverController {
    /// Reports cursor enter/exit over the shape.
    var onHoverChange: ((Bool) -> Void)?
    /// Reports cursor enter/exit over a safe zone. Called on the next run loop turn, never from
    /// inside `setHitRect`, which runs mid-transition.
    var onSafeZoneChange: ((Bool) -> Void)?
    /// While something is being dragged, the shape reaches `Metrics.dropReach` further.
    var isDragging = false {
        didSet { update(cursorMoved: false) }
    }

    private let panel: NSPanel
    private var hitRect: CGRect = .zero
    /// Areas that take clicks without counting as a hover (the activity bubbles beside the notch).
    private var clickRects: [CGRect] = []
    private var safeZones: [CGRect] = []
    private var isInside = false
    private var isInSafeZone = false
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

    /// Sets the interactive area (screen coordinates) to the shape's new target frame, plus areas
    /// that only need to be clickable, and the safe zones that take precedence over both.
    func setHitRect(_ rect: CGRect, clickable: [CGRect] = [], safeZones: [CGRect] = []) {
        hitRect = rect
        clickRects = clickable
        self.safeZones = safeZones
        update(cursorMoved: false)
    }

    private func update(cursorMoved: Bool) {
        let location = NSEvent.mouseLocation
        let reach = isDragging ? -Metrics.dropReach : 0
        // A drag still finds the notch anywhere; dropping onto a menu bar icon isn't a thing.
        let inSafeZone = !isDragging && safeZones.contains { $0.contains(location) }
        let inside = !inSafeZone && hitRect.insetBy(dx: reach, dy: reach).contains(location)
        let clickable = inside || (!inSafeZone && clickRects.contains { $0.contains(location) })
        if panel.ignoresMouseEvents == clickable {
            panel.ignoresMouseEvents = !clickable
        }
        if inSafeZone != isInSafeZone {
            isInSafeZone = inSafeZone
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onSafeZoneChange?(inSafeZone) }
            }
        }
        guard inside != isInside else { return }
        // A shape that grows under a resting cursor (a live activity appearing) shouldn't count as
        // a hover. Entering requires real movement; leaving is reported either way.
        if inside && !cursorMoved { return }
        isInside = inside
        onHoverChange?(inside)
    }
}
