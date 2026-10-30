import AppKit
import SwiftUI

/// Owns the panel and keeps hover and click handling in step with the view model.
///
/// The panel has one fixed frame per display, big enough for the largest state plus room for the
/// spring's overshoot, and it never resizes during use. The shape is top-centered inside it, so it
/// can only ever grow out of the notch's center. `HoverController` makes everything outside the
/// visible shape click-through.
@MainActor
final class NotchWindowController: NotchViewModelDelegate {
    private let panel = NotchPanel()
    private let model: NotchViewModel
    private let hover: HoverController
    private let dragDetector = DragDetector()
    private var clickAwayMonitor: Any?

    init(model: NotchViewModel) {
        self.model = model
        self.hover = HoverController(panel: panel)

        // Wrapped in a plain container: as the window's direct content view, NSHostingView tries to
        // manage the panel's content size limits, which loops forever on a panel straddling the notch.
        let hostingView = NotchHostingView(rootView: NotchContainerView(model: model))
        let container = NSView()
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container

        hover.onHoverChange = { [weak model] isInside in
            model?.hoverChanged(isInside: isInside)
        }
        model.delegate = self
        dragDetector.onChange = { [weak self] isDragging in
            self?.hover.isDragging = isDragging
            self?.model.setDragging(isDragging)
        }

        placePanel()
        panel.orderFrontRegardless()
        hover.start()
        dragDetector.start()
    }

    // MARK: NotchViewModelDelegate

    func notchWillTransition(to state: NotchState, layout: NotchLayout, satellites: [SatelliteSide]) {
        // Hit-test against where the shape is going, so the area it's leaving stops counting at once.
        updateHitRects(layout: layout, satellites: satellites)
        if state == .expanded { installClickAwayMonitor() } else { removeClickAwayMonitor() }
    }

    func notchGeometryDidChange() {
        placePanel()
    }

    func notchSuppressionDidChange() {
        updateHitRects(layout: model.layout, satellites: model.visibleSatellites.map(\.side))
        if model.isSuppressed { removeClickAwayMonitor() }
    }

    /// Nothing is interactive while hidden for a full-screen app: the top edge belongs to its menu bar.
    /// The bubbles take clicks but don't open the notch on hover.
    private func updateHitRects(layout: NotchLayout, satellites: [SatelliteSide]) {
        guard !model.isSuppressed else {
            hover.setHitRect(.zero)
            return
        }
        hover.setHitRect(
            layout.hitRect(in: model.geometry),
            clickable: satellites.map { layout.satelliteHitRect($0, in: model.geometry) }
        )
    }

    // MARK: Private

    private func placePanel() {
        panel.setFrame(NotchLayout.panelFrame(in: model.geometry), display: true)
        updateHitRects(layout: model.layout, satellites: model.visibleSatellites.map(\.side))
    }

    /// Clicks in other apps collapse the panel. Clicks outside the shape fall through to those apps,
    /// so this covers everywhere but the shape. Global mouse monitors need no Accessibility permission,
    /// and this one only exists while expanded.
    private func installClickAwayMonitor() {
        guard clickAwayMonitor == nil else { return }
        clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.collapse() }
        }
    }

    private func removeClickAwayMonitor() {
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
        clickAwayMonitor = nil
    }
}
