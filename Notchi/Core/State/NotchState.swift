/// The three presentations of the notch surface.
enum NotchState: Equatable, Sendable {
    /// Nothing to show: tucked behind the hardware notch, or a small resting island.
    case idle
    /// A live activity owns the slots left and right of the notch.
    case compact
    /// The full panel, opened by hover or click.
    case expanded

    /// Size order: idle < compact < expanded.
    var rank: Int {
        switch self {
        case .idle: 0
        case .compact: 1
        case .expanded: 2
        }
    }

    /// The single rule that decides the state. User intent wins; otherwise any live activity shows compact.
    static func resolve(expandRequested: Bool, hasLiveActivity: Bool) -> NotchState {
        if expandRequested { return .expanded }
        return hasLiveActivity ? .compact : .idle
    }
}
