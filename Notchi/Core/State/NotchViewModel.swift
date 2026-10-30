import SwiftUI

/// Told about transitions so hover hit-testing and click-away follow the shape.
@MainActor
protocol NotchViewModelDelegate: AnyObject {
    /// Called right before an animated change to `state`, `layout` or the bubbles. `satellites` are
    /// the sides that will show a bubble.
    func notchWillTransition(to state: NotchState, layout: NotchLayout, satellites: [SatelliteSide])
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
    /// Other live activities, as bubbles either side of the compact notch.
    private(set) var satellites = SatelliteSlots()
    /// The module compact mode shows. Committed here with each transition rather than read live
    /// from the registry, so new content waits for the animation that brings it in (a reopen, say).
    private(set) var compactModuleID: String?
    /// Bumped by every swap, so the surface plays its warp toward `lastSwapSide`.
    private(set) var swapCount = 0
    private(set) var lastSwapSide = SatelliteSide.trailing

    let registry: ModuleRegistry
    @ObservationIgnored weak var delegate: NotchViewModelDelegate?

    @ObservationIgnored private var expandRequested = false
    /// Squeezes out the replaced activity's bubble once the clicked one has been absorbed.
    @ObservationIgnored private var swapTask: Task<Void, Never>?
    /// Reopens the notch once the close before it has played.
    @ObservationIgnored private var reopenTask: Task<Void, Never>?
    /// The module compact mode last showed, and whether that was a toast. A toast arriving over
    /// another activity, or leaving one behind, reopens the notch.
    @ObservationIgnored private var shownForeground: (id: String, isToast: Bool)?
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesObserver: NSObjectProtocol?
    /// While a size or appearance slider moves in Settings, the notch shows the state it applies to.
    @ObservationIgnored private var sizePreview: NotchState?
    @ObservationIgnored private var sizePreviewTask: Task<Void, Never>?
    @ObservationIgnored private var lastSizes = (compact: Preferences.compactSideWidth, expanded: Preferences.expandedWidth)
    @ObservationIgnored private var lastLook = (clarity: Preferences.glassClarity, edge: Preferences.edgeHighlight, blend: Preferences.notchBlend)
    @ObservationIgnored private var lastCorners = (bottom: Preferences.notchCornerRadius, top: Preferences.notchTopCurve)
    @ObservationIgnored private var lastAlignment = Preferences.compactAlignment
    @ObservationIgnored private var lastMotion = (style: Preferences.openAnimation, duration: Preferences.openDuration, bounce: Preferences.openBounce)

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

    var compactModule: (any NotchModule)? {
        compactModuleID.flatMap(registry.module(withID:))
    }

    /// One bubble beside the notch.
    struct Satellite {
        let side: SatelliteSide
        let module: any NotchModule
    }

    /// The bubbles on screen: only beside the compact notch, and never over a full-screen app.
    var visibleSatellites: [Satellite] {
        Self.visibleSides(state: state, satellites: satellites, suppressed: isSuppressed).compactMap { side in
            satellites[side].flatMap(registry.module(withID:)).map { Satellite(side: side, module: $0) }
        }
    }

    private static func visibleSides(state: NotchState, satellites: SatelliteSlots, suppressed: Bool) -> [SatelliteSide] {
        state == .compact && !suppressed ? satellites.occupied : []
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

    /// Click on a bubble: its activity swaps places with the one in the middle, and the one it
    /// replaces takes the bubble's slot.
    func bringToFront(_ id: String) {
        guard state == .compact, !isSuppressed, reopenTask == nil, let side = satellites.side(of: id), let current = registry.primary?.id else { return }
        let previousPreference = registry.preferredID
        registry.preferredID = id
        // Something more pressing (an urgent timer) keeps the middle; nothing moves.
        guard registry.primary?.id == id else {
            registry.preferredID = previousPreference
            return
        }
        var swapped = satellites
        swapped[side] = current
        let newLayout = targetLayout(for: state)
        delegate?.notchWillTransition(
            to: state,
            layout: newLayout,
            satellites: Self.visibleSides(state: state, satellites: swapped, suppressed: isSuppressed)
        )
        // First the clicked bubble merges into the notch, as the notch gulps and changes content…
        var absorbed = satellites
        absorbed[side] = nil
        lastSwapSide = side
        withAnimation(Motion.swap) {
            swapCount += 1
            layout = newLayout
            compactModuleID = registry.foreground?.id
        }
        withAnimation(Motion.satelliteAbsorb) { satellites = absorbed }
        // …then, a beat later, the activity it replaced squeezes out into the same slot.
        swapTask?.cancel()
        swapTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.swapBeat)
            guard let self, !Task.isCancelled else { return }
            self.swapTask = nil
            if self.satellites[side] == nil, self.registry.satelliteCandidates.contains(where: { $0.id == current }) {
                withAnimation(Motion.satelliteEmerge) { self.satellites[side] = current }
            }
            self.reevaluate()
        }
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
        // A pick lasts as long as its activity; next time, the usual priorities decide again.
        if let preferred = registry.preferredID, registry.module(withID: preferred)?.liveActivity == nil {
            registry.preferredID = nil
        }
        let foreground = registry.foreground
        let activity = foreground?.liveActivity
        // In full screen only opted-in activities (the volume HUD) may show, and never expanded.
        let visibleActivity = isSuppressed ? activity.flatMap { $0.showsInFullScreen ? $0 : nil } : activity
        var target = NotchState.resolve(expandRequested: expandRequested && !isSuppressed, hasLiveActivity: visibleActivity != nil)
        if let sizePreview, sizePreview.rank > target.rank, !isSuppressed { target = sizePreview }

        // While closed for a reopen, wait for it, unless the user opens the panel.
        if reopenTask != nil {
            guard target == .expanded else { return }
            cancelReopen()
        }
        let shown = target == .compact ? foreground.map { (id: $0.id, isToast: activity?.priority == .transient) } : nil
        defer { shownForeground = shown }
        if let shown, let previous = shownForeground, state == .compact, previous.id != shown.id,
           previous.isToast || shown.isToast, Motion.reopensForToasts {
            reopen()
            return
        }
        let newLayout = targetLayout(for: target)
        let newCompactID = target == .compact ? foreground?.id : nil
        // Mid-swap the slots are the swap's to manage; it re-evaluates when it's done.
        let newSatellites = swapTask == nil ? satellites.reconciled(with: registry.satelliteCandidates.map(\.id)) : satellites
        guard target != state || newLayout != layout || newSatellites != satellites || newCompactID != compactModuleID else { return }
        transition(to: target, layout: newLayout, satellites: newSatellites)
    }

    /// A toast takes over compact mode (or hands it back): the notch closes into the hardware notch
    /// as the old content fades, then springs open again with the new, like a fresh live activity.
    private func reopen() {
        let closed = targetLayout(for: .idle)
        delegate?.notchWillTransition(
            to: state,
            layout: closed,
            satellites: Self.visibleSides(state: state, satellites: satellites, suppressed: isSuppressed)
        )
        withAnimation(Motion.reopenClose) {
            compactModuleID = nil
            layout = closed
        }
        reopenTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.reopenBeat)
            guard let self, !Task.isCancelled else { return }
            self.reopenTask = nil
            self.reevaluate()
        }
    }

    private func cancelReopen() {
        reopenTask?.cancel()
        reopenTask = nil
    }

    private func transition(to target: NotchState, layout newLayout: NotchLayout, satellites newSatellites: SatelliteSlots) {
        let opening = target == .expanded && state != .expanded
        if opening {
            if let foreground = registry.foreground?.id { selectedModuleID = foreground }
            Haptics.expand()
        }

        delegate?.notchWillTransition(
            to: target,
            layout: newLayout,
            satellites: Self.visibleSides(state: target, satellites: newSatellites, suppressed: isSuppressed)
        )

        let growing = newLayout.size.height > layout.size.height
        withAnimation(growing ? Motion.expand : Motion.collapse) {
            state = target
            layout = newLayout
            compactModuleID = target == .compact ? registry.foreground?.id : nil
        }
        // New bubbles pop out of the notch with a wobble; leaving ones merge back in cleanly.
        let addsBubble = newSatellites.occupied.contains { side in
            newSatellites[side].map { satellites.side(of: $0) == nil } == true
        }
        withAnimation(addsBubble ? Motion.satelliteEmerge : Motion.satelliteAbsorb) {
            satellites = newSatellites
        }
    }

    private func targetLayout(for state: NotchState) -> NotchLayout {
        let activity = registry.foreground?.liveActivity
        return NotchLayout.make(
            state: state,
            geometry: geometry,
            sideWidth: activity?.sideWidth ?? Preferences.compactSideWidth,
            expandedWidth: Preferences.expandedWidth,
            belowHeight: activity?.belowHeight ?? 0,
            cornerRadius: Preferences.notchCornerRadius,
            topCurve: Preferences.notchTopCurve
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
        // Appearance sliders open the panel too, since that's where the glass shows best.
        let look = (clarity: Preferences.glassClarity, edge: Preferences.edgeHighlight, blend: Preferences.notchBlend)
        if look != lastLook {
            showSizePreview(.expanded)
            lastLook = look
        }
        let corners = (bottom: Preferences.notchCornerRadius, top: Preferences.notchTopCurve)
        if corners != lastCorners {
            showSizePreview(.expanded)
            lastCorners = corners
        }
        if Preferences.compactAlignment != lastAlignment {
            showSizePreview(.compact)
            lastAlignment = Preferences.compactAlignment
        }
        let motion = (style: Preferences.openAnimation, duration: Preferences.openDuration, bounce: Preferences.openBounce)
        if motion != lastMotion {
            replayOpening()
            lastMotion = motion
        }
        reevaluate()
    }

    /// Shows off a new open animation: closes (the caller's `reevaluate` does that), then springs
    /// open once the setting has been still for a moment.
    private func replayOpening() {
        sizePreview = nil
        sizePreviewTask?.cancel()
        sizePreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled, let self else { return }
            self.showSizePreview(.expanded)
            self.reevaluate()
        }
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
            _ = registry.satelliteCandidates.map(\.liveActivity)
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
        compactModuleID = newState == .compact ? registry.foreground?.id : nil
        satellites = satellites.reconciled(with: registry.satelliteCandidates.map(\.id))
    }
}
