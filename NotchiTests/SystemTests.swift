import Foundation
import IOKit.ps
import Testing
@testable import Notchi

struct BatteryTests {
    private func description(current: Int = 76, max: Int = 100, ac: Bool, charging: Bool, toFull: Int = 64, toEmpty: Int = -1) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: current, kIOPSMaxCapacityKey: max,
            kIOPSPowerSourceStateKey: ac ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
            kIOPSIsChargingKey: charging, kIOPSIsChargedKey: false,
            kIOPSTimeToFullChargeKey: toFull, kIOPSTimeToEmptyKey: toEmpty,
        ]
    }

    @Test func decodesIOKitDescription() throws {
        let charging = try #require(BatteryState(description: description(ac: true, charging: true)))
        #expect(charging.percent == 76)
        #expect(charging.isPluggedIn && charging.isCharging)
        #expect(charging.minutesRemaining == 64)

        let draining = try #require(BatteryState(description: description(ac: false, charging: false, toEmpty: -1)))
        #expect(draining.minutesRemaining == nil)                     // -1 means "still estimating"
        #expect(BatteryState(description: [kIOPSTypeKey: "UPS"]) == nil)
    }

    @Test func plugInToasts() {
        let onBattery = BatteryState(level: 0.5, isPluggedIn: false, isCharging: false)
        let pluggedIn = BatteryState(level: 0.5, isPluggedIn: true, isCharging: true)
        #expect(BatteryAlerts.toast(from: onBattery, to: pluggedIn) == .charging(pluggedIn))
        #expect(BatteryAlerts.toast(from: pluggedIn, to: onBattery) == nil)
        #expect(BatteryAlerts.toast(from: nil, to: pluggedIn) == nil)   // launch isn't a change
    }

    @Test func lowBatteryToastsOnceAtEachThreshold() {
        func at(_ percent: Int) -> BatteryState { BatteryState(level: Double(percent) / 100, isPluggedIn: false, isCharging: false) }
        #expect(BatteryAlerts.toast(from: at(21), to: at(20)) == .lowBattery(at(20)))
        #expect(BatteryAlerts.toast(from: at(20), to: at(19)) == nil)
        #expect(BatteryAlerts.toast(from: at(11), to: at(10)) == .lowBattery(at(10)))
        #expect(BatteryAlerts.toast(from: at(50), to: at(49)) == nil)
    }

    @Test @MainActor func subtitles() {
        #expect(SystemExpandedView.batterySubtitle(BatteryState(level: 0.5, isPluggedIn: true, isCharging: true, minutesRemaining: 75)) == "Charging · 1h 15m to full")
        #expect(SystemExpandedView.batterySubtitle(BatteryState(level: 0.5, isPluggedIn: false, isCharging: false, minutesRemaining: 190)) == "3h 10m left")
        #expect(SystemExpandedView.batterySubtitle(BatteryState(level: 1, isPluggedIn: true, isCharging: false, isCharged: true)) == "Charged")
        #expect(SystemExpandedView.batterySubtitle(BatteryState(level: 0.8, isPluggedIn: true, isCharging: false)) == "Plugged in, not charging")
    }
}

struct MediaKeyTests {
    /// Builds `data1` the way the system encodes special keys.
    private func data1(code: Int, down: Bool, isRepeat: Bool = false) -> Int {
        (code << 16) | ((down ? 0xA : 0xB) << 8) | (isRepeat ? 1 : 0)
    }

    @Test func decodesKeys() {
        #expect(MediaKeyEvent(data1: data1(code: 0, down: true))?.key == .volumeUp)
        #expect(MediaKeyEvent(data1: data1(code: 1, down: true))?.key == .volumeDown)
        #expect(MediaKeyEvent(data1: data1(code: 7, down: true))?.key == .mute)
        #expect(MediaKeyEvent(data1: data1(code: 2, down: true))?.key == .brightnessUp)
        #expect(MediaKeyEvent(data1: data1(code: 3, down: true))?.key == .brightnessDown)
        #expect(MediaKeyEvent(data1: data1(code: 16, down: true)) == nil)  // play/pause: not ours
    }

    @Test func decodesStateAndRepeat() {
        let up = MediaKeyEvent(data1: data1(code: 0, down: false))
        #expect(up?.isDown == false)
        #expect(MediaKeyEvent(data1: data1(code: 0, down: true, isRepeat: true))?.isRepeat == true)
        #expect(MediaKeyEvent(data1: (0 << 16) | (0x5 << 8)) == nil)        // unknown key state
    }

    @Test func stepsSnapToGrid() {
        #expect(LevelStep.next(from: 0.5, up: true, fine: false) == 0.5625)
        #expect(LevelStep.next(from: 0.51, up: true, fine: false) == 0.5625)  // snaps, like macOS
        #expect(LevelStep.next(from: 1, up: true, fine: false) == 1)
        #expect(LevelStep.next(from: 0.02, up: false, fine: false) == 0)
        #expect(LevelStep.next(from: 0.5, up: true, fine: true) == 0.515625)
    }
}

struct FocusTests {
    @Test func extractsFocusName() {
        #expect(FocusMonitor.focusName(fromDescription: "Focus, Do Not Disturb") == "Do Not Disturb")
        #expect(FocusMonitor.focusName(fromDescription: "Work") == "Work")
        #expect(FocusMonitor.focusName(fromDescription: "Focus") == nil)
        #expect(FocusMonitor.focusName(fromDescription: nil) == nil)
    }

    @Test func toastKinds() {
        #expect(SystemToast.volume(level: 0.2, isMuted: false).isSameKind(as: .volume(level: 0.9, isMuted: true)))
        let volume = SystemToast.volume(level: 0.2, isMuted: false)
        let brightness = SystemToast.brightness(level: 0.2)
        #expect(volume.kind == .volume && brightness.kind == .brightness)
        #expect(volume.isSameKind(as: brightness) == false)
        #expect(volume.isSameKind(as: nil) == false)
    }
}
