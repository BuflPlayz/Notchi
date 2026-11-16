import AppKit

/// Hover detection and click-through for the notch panel.
///
/// The panel is large and never resizes, so animations can't shift. Only the visible shape should
/// be interactive, though. Mouse-moved monitors compare the cursor with the shape's current frame.
/// Inside, the panel takes mouse events. Outside, it ignores them, so they fall through to whatever
/// is underneath. Monitors only fire while the mouse moves, so this costs nothing at rest.
///
/// Safe zones are the menu bar the compact notch covers: beside the physical notch, and around the
/// activity bubbles. Once the pointer has rested in one for its delay (`menuBarStepAsideDelay`
/// beside the notch, `bubbleStepAsideDelay` around a bubble), the panel stops taking the mouse there
/// and reports it, so the notch can step aside and uncover the menu bar icons underneath. While it
/// waits, the shape and bubbles take clicks but don't count as a hover, so the notch doesn't open.
/// Once stepped aside, every safe zone counts at once.
///
/// A press that starts on the panel freezes all of this until the button comes up, so the pointer
/// can swipe from the notch toward a bubble (across the menu bar beside it) without the panel
/// letting go of the drag or the notch stepping aside mid-swipe.
@MainActor
final class HoverController {
    /// Reports cursor enter/exit over the shape.
    var onHoverChange: ((Bool) -> Void)?
    /// Reports cursor enter/exit over a safe zone. Called on the next run loop turn, never from
    /// inside `setHitRect`, which runs mid-transition.
    var onSafeZoneChange: ((Bool) -> Void)?
    /// Reports the left button going down on the panel, and coming back up.
    var onPressChange: ((Bool) -> Void)?
    /// While something is being dragged, the shape reaches `Metrics.dropReach` further.
    var isDragging = false {
        didSet { update(cursorMoved: false) }
    }

    private let panel: NSPanel
    private var hitRect: CGRect = .zero
    /// Areas that take clicks without counting as a hover (the activity bubbles beside the notch).
    private var clickRects: [CGRect] = []
    private var safeZones: [CGRect] = []
    private var bubbleZones: [CGRect] = []
    /// The kind of safe zone the pointer is waiting in, and whether its delay has run out (it then
    /// counts as a safe zone until the pointer leaves the safe zones).
    private var waitingZone: SafeZone?
    private var zoneArmed = false
    private var zoneTimer: Timer?
    private var isInside = false
    private var isInSafeZone = false
    private var isPressing = false
    /// After a press, the safe zone waits for the pointer to move: a swipe that ends beside the
    /// notch shouldn't tuck away the activity it just brought in.
    private var safeZoneWaitsForMove = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pressMonitors: [Any] = []

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
        // Local monitors see an event before the panel does, so the press is known before any
        // gesture handles it. The release can land elsewhere if the panel lost it, hence the global one.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.setPressing(event.type == .leftMouseDown && event.window === self.panel)
            }
            return event
        }) {
            pressMonitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.setPressing(false) }
        }) {
            pressMonitors.append(monitor)
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        pressMonitors.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
        pressMonitors.removeAll()
    }

    /// Sets the interactive area (screen coordinates) to the shape's new target frame, plus areas
    /// that only need to be clickable, and the safe zones that take precedence over both.
    func setHitRect(_ rect: CGRect, clickable: [CGRect] = [], safeZones: [CGRect] = [], bubbleZones: [CGRect] = []) {
        hitRect = rect
        clickRects = clickable
        self.safeZones = safeZones
        self.bubbleZones = bubbleZones
        update(cursorMoved: false)
    }

    private func setPressing(_ pressing: Bool) {
        guard pressing != isPressing else { return }
        isPressing = pressing
        onPressChange?(pressing)
        // A click starts the wait over (a bubble may have just swapped in something new).
        disarmZone()
        if !pressing {
            safeZoneWaitsForMove = true
            update(cursorMoved: false)
        }
    }

    private func update(cursorMoved: Bool) {
        // Mid-press the panel keeps the mouse and nothing changes; the release catches up.
        if isPressing { return }
        if cursorMoved { safeZoneWaitsForMove = false }
        let location = NSEvent.mouseLocation
        let reach = isDragging ? -Metrics.dropReach : 0
        // A drag still finds the notch anywhere; dropping onto a menu bar icon isn't a thing.
        let zone: SafeZone? = isDragging ? nil
            : safeZones.contains { $0.contains(location) } ? .besideNotch
            : bubbleZones.contains { $0.contains(location) } ? .bubble
            : nil
        if let zone {
            // Waiting starts once the pointer has moved since a press (see `safeZoneWaitsForMove`).
            if !isInSafeZone && !zoneArmed && zone != waitingZone && !safeZoneWaitsForMove { wait(in: zone) }
        } else {
            disarmZone()
        }
        let inSafeZone = zone != nil && (zoneArmed || isInSafeZone)
        let isWaiting = zone != nil && !inSafeZone
        let onShape = hitRect.insetBy(dx: reach, dy: reach).contains(location)
        let inside = !inSafeZone && !isWaiting && onShape
        let clickable = !inSafeZone && (onShape || clickRects.contains { $0.contains(location) })
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

    /// Starts the wait for the kind of safe zone the pointer is in. Without a delay it counts at once.
    private func wait(in zone: SafeZone) {
        disarmZone()
        waitingZone = zone
        let delay = zone == .besideNotch ? Preferences.menuBarStepAsideDelay : Preferences.bubbleStepAsideDelay
        guard delay > 0 else {
            zoneArmed = true
            return
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.zoneTimer = nil
                self.zoneArmed = true
                self.update(cursorMoved: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        zoneTimer = timer
    }

    private func disarmZone() {
        zoneTimer?.invalidate()
        zoneTimer = nil
        waitingZone = nil
        zoneArmed = false
    }
}

/// The two kinds of menu bar the compact notch covers, each with its own wait before stepping aside.
private enum SafeZone {
    /// Beside the physical notch (or resting island).
    case besideNotch
    /// Around an activity bubble, and the gap between it and the notch.
    case bubble
}
