import SwiftUI

/// Told about transitions so hover hit-testing and click-away follow the shape.
@MainActor
protocol NotchViewModelDelegate: AnyObject {
    /// Called right before an animated change to `state` and `layout`.
    func notchWillTransition(to state: NotchState, layout: NotchLayout)
    /// The main display changed; the panel needs re-placing.
    func notchGeometryDidChange()
    /// Full-screen hiding turned on or off; hover and clicks follow.
    func notchSuppressionDidChange()
}

/// The notch's state machine. Inputs are hover/click intent and the modules' live activities;
/// the output is a `NotchState` plus the `NotchLayout` the view animates to.
@MainActor
@Observable
final class NotchViewModel {
    private(set) var geometry: NotchGeometry
    private(set) var state: NotchState = .idle
    /// Stored (not derived) so changes always happen inside `withAnimation`.
    private(set) var layout: NotchLayout
    /// Module shown in the expanded panel.
    var selectedModuleID: String?
    /// True while a full-screen app is in front (and "Hide in full screen" is on): the notch stays
    /// out of the way except for activities that opt in, and hover is ignored.
    private(set) var isSuppressed = false

    let registry: ModuleRegistry
    @ObservationIgnored weak var delegate: NotchViewModelDelegate?

    @ObservationIgnored private var expandRequested = false
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesObserver: NSObjectProtocol?
    /// While a size slider moves in Settings, the notch shows the state that size applies to.
    @ObservationIgnored private var sizePreview: NotchState?
    @ObservationIgnored private var sizePreviewTask: Task<Void, Never>?
    @ObservationIgnored private var lastSizes = (compact: Preferences.compactSideWidth, expanded: Preferences.expandedWidth)

    init(geometry: NotchGeometry, registry: ModuleRegistry) {
        self.geometry = geometry
        self.registry = registry
        self.layout = NotchLayout.make(state: .idle, geometry: geometry)
        observeRegistry()
        observePreferences()
        reevaluate()
    }

    var selectedModule: (any NotchModule)? {
        selectedModuleID.flatMap(registry.module(withID:)) ?? registry.foreground ?? registry.modules.first
    }

    // MARK: Inputs

    /// Cursor entered or left the notch. Debounced so a passing cursor doesn't open it.
    func hoverChanged(isInside: Bool) {
        hoverTask?.cancel()
        if isSuppressed { return }
        // Leaving cancels a pending expand right away; there's nothing to wait for if we're not expanded.
        if !isInside && !expandRequested { return }
        // With "Open on hover" off, only a click opens; moving away still closes.
        if isInside && !Preferences.openOnHover { return }
        let delay = isInside ? Preferences.expandDelay : Preferences.collapseDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.setExpandRequested(isInside)
        }
    }

    /// Hides or shows the notch for full-screen apps.
    func setSuppressed(_ suppressed: Bool) {
        guard suppressed != isSuppressed else { return }
        isSuppressed = suppressed
        hoverTask?.cancel()
        if suppressed { expandRequested = false }
        delegate?.notchSuppressionDidChange()
        reevaluate()
    }

    /// Click on the notch: open without waiting for the hover delay.
    func expandNow() {
        guard !isSuppressed else { return }
        hoverTask?.cancel()
        setExpandRequested(true)
    }

    /// Click-away or Escape.
    func collapse() {
        hoverTask?.cancel()
        setExpandRequested(false)
    }

    /// The main display changed (plugged in, lid closed, resolution). Snap, don't animate.
    func updateGeometry(_ newGeometry: NotchGeometry) {
        guard newGeometry != geometry else { return }
        geometry = newGeometry
        layout = targetLayout(for: state)
        delegate?.notchGeometryDidChange()
    }

    // MARK: State machine

    private func setExpandRequested(_ requested: Bool) {
        guard expandRequested != requested else { return }
        expandRequested = requested
        reevaluate()
    }

    private func reevaluate() {
        let activity = registry.foreground?.liveActivity
        // In full screen only opted-in activities (the volume HUD) may show, and never expanded.
        let visibleActivity = isSuppressed ? activity.flatMap { $0.showsInFullScreen ? $0 : nil } : activity
        var target = NotchState.resolve(expandRequested: expandRequested && !isSuppressed, hasLiveActivity: visibleActivity != nil)
        if let sizePreview, sizePreview.rank > target.rank, !isSuppressed { target = sizePreview }
        let newLayout = targetLayout(for: target)
        guard target != state || newLayout != layout else { return }
        transition(to: target, layout: newLayout)
    }

    private func transition(to target: NotchState, layout newLayout: NotchLayout) {
        let opening = target == .expanded && state != .expanded
        if opening {
            if let foreground = registry.foreground?.id { selectedModuleID = foreground }
            Haptics.expand()
        }

        delegate?.notchWillTransition(to: target, layout: newLayout)

        let growing = newLayout.size.height > layout.size.height
        withAnimation(growing ? Motion.expand : Motion.collapse) {
            state = target
            layout = newLayout
        }
    }

    private func targetLayout(for state: NotchState) -> NotchLayout {
        let activity = registry.foreground?.liveActivity
        return NotchLayout.make(
            state: state,
            geometry: geometry,
            sideWidth: activity?.sideWidth ?? Preferences.compactSideWidth,
            expandedWidth: Preferences.expandedWidth,
            belowHeight: activity?.belowHeight ?? 0
        )
    }

    /// Size settings apply live: the surface springs to the new width while Settings is open.
    private func observePreferences() {
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesChanged() }
        }
    }

    private func preferencesChanged() {
        let sizes = (compact: Preferences.compactSideWidth, expanded: Preferences.expandedWidth)
        if sizes != lastSizes {
            showSizePreview(sizes.expanded != lastSizes.expanded ? .expanded : .compact)
            lastSizes = sizes
        }
        reevaluate()
    }

    /// Holds the preview state until the slider has been still for a moment.
    private func showSizePreview(_ state: NotchState) {
        sizePreview = state
        sizePreviewTask?.cancel()
        sizePreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            self.sizePreview = nil
            self.reevaluate()
        }
    }

    /// Re-run the state machine whenever any module's live activity changes.
    private func observeRegistry() {
        withObservationTracking {
            _ = registry.foreground?.liveActivity
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.reevaluate()
                self?.observeRegistry()
            }
        }
    }

    // MARK: Previews

    /// Jumps straight to a state without animating or notifying the delegate. For previews.
    func setStateForPreview(_ newState: NotchState) {
        expandRequested = newState == .expanded
        state = newState
        layout = targetLayout(for: newState)
    }
}
