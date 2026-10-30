import Foundation

/// A short-lived message the System module shows in compact mode.
enum SystemToast: Equatable, Sendable {
    case volume(level: Double, isMuted: Bool)
    case brightness(level: Double)
    case charging(BatteryState)
    case lowBattery(BatteryState)

    /// How long it stays. HUDs disappear quickly; status changes linger a little.
    var duration: Duration {
        switch self {
        case .volume, .brightness: .milliseconds(1500)
        case .charging: .seconds(3)
        case .lowBattery: .seconds(5)
        }
    }

    /// Compact slot width the toast needs.
    var sideWidth: CGFloat {
        switch self {
        case .volume, .brightness: HUDMetrics.sideWidth
        case .charging: BatteryToastMetrics.chargingWidth
        case .lowBattery: BatteryToastMetrics.lowWidth
        }
    }

    enum Kind: Equatable { case volume, brightness, charging, lowBattery }

    var kind: Kind {
        switch self {
        case .volume: .volume
        case .brightness: .brightness
        case .charging: .charging
        case .lowBattery: .lowBattery
        }
    }

    /// Whether two toasts are the same kind, so a new one replaces the old in place.
    func isSameKind(as other: SystemToast?) -> Bool {
        kind == other?.kind
    }
}

/// Decides which battery changes deserve a toast.
enum BatteryAlerts {
    /// Battery percentages that trigger a low-battery toast when crossed downward on battery power.
    static let lowThresholds = [20, 10, 5]

    static func toast(from old: BatteryState?, to new: BatteryState?) -> SystemToast? {
        guard let old, let new else { return nil }   // first reading: nothing changed
        if new.isPluggedIn && !old.isPluggedIn {
            return .charging(new)
        }
        if !new.isPluggedIn, lowThresholds.contains(where: { new.percent <= $0 && old.percent > $0 }) {
            return .lowBattery(new)
        }
        return nil
    }
}
