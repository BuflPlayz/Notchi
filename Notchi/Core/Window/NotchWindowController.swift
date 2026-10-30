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

        placePanel()
        panel.orderFrontRegardless()
        hover.start()
    }

    // MARK: NotchViewModelDelegate

    func notchWillTransition(to state: NotchState, layout: NotchLayout) {
        // Hit-test against where the shape is going, so the area it's leaving stops counting at once.
        hover.setHitRect(hitRect(for: layout))
        if state == .expanded { installClickAwayMonitor() } else { removeClickAwayMonitor() }
    }

    func notchGeometryDidChange() {
        placePanel()
    }

    func notchSuppressionDidChange() {
        hover.setHitRect(hitRect(for: model.layout))
        if model.isSuppressed { removeClickAwayMonitor() }
    }

    /// Nothing is interactive while hidden for a full-screen app: the top edge belongs to its menu bar.
    private func hitRect(for layout: NotchLayout) -> CGRect {
        model.isSuppressed ? .zero : layout.hitRect(in: model.geometry)
    }

    // MARK: Private

    private func placePanel() {
        panel.setFrame(NotchLayout.panelFrame(in: model.geometry), display: true)
        hover.setHitRect(hitRect(for: model.layout))
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
