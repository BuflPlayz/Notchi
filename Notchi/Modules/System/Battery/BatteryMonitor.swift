import Foundation
import IOKit.ps

/// The internal battery's state.
struct BatteryState: Equatable, Sendable {
    /// 0…1.
    var level: Double
    var isPluggedIn: Bool
    var isCharging: Bool
    var isCharged: Bool
    /// Minutes until empty (on battery) or full (charging); nil while macOS is still estimating.
    var minutesRemaining: Int?

    var percent: Int { Int((level * 100).rounded()) }

    /// Decodes one entry from `IOPSGetPowerSourceDescription`. Nil for anything but an internal battery.
    init?(description: [String: Any]) {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
        else { return nil }
        level = min(max(Double(current) / Double(maximum), 0), 1)
        isPluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        isCharged = description[kIOPSIsChargedKey] as? Bool ?? false
        let minutes = description[isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
        minutesRemaining = minutes.flatMap { $0 > 0 ? $0 : nil }
    }

    init(level: Double, isPluggedIn: Bool, isCharging: Bool, isCharged: Bool = false, minutesRemaining: Int? = nil) {
        self.level = level
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.minutesRemaining = minutesRemaining
    }
}

/// Watches the battery through IOKit's power-source notifications, so nothing is polled.
/// Macs without a battery report nil and never notify.
@MainActor
final class BatteryMonitor {
    var onChange: ((BatteryState?) -> Void)?
    private(set) var state: BatteryState?
    private var source: CFRunLoopSource?

    func start() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            // Delivered on the main run loop, where the source was added.
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)
        guard let created else { return }
        let runLoopSource = created.takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        source = runLoopSource
        refresh()
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    private func refresh() {
        let newState = Self.read()
        guard newState != state else { return }
        state = newState
        onChange?(newState)
    }

    private static func read() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
               let state = BatteryState(description: description) {
                return state
            }
        }
        return nil
    }
}
