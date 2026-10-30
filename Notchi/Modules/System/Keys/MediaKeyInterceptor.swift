import AppKit
import CoreGraphics

/// A volume or brightness key press, decoded from an `NX_SYSDEFINED` event.
struct MediaKeyEvent: Equatable, Sendable {
    enum Key: Equatable, Sendable {
        case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
    }

    var key: Key
    var isDown: Bool
    var isRepeat: Bool

    /// Decodes `NSEvent.data1` of a system-defined event with subtype 8 (special keys).
    /// Layout: key code in the high 16 bits, then key state (0xA down, 0xB up), then a repeat flag.
    init?(data1: Int) {
        let code = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        guard state == 0xA || state == 0xB else { return nil }
        switch code {
        case 0: key = .volumeUp          // NX_KEYTYPE_SOUND_UP
        case 1: key = .volumeDown        // NX_KEYTYPE_SOUND_DOWN
        case 2: key = .brightnessUp      // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: key = .brightnessDown    // NX_KEYTYPE_BRIGHTNESS_DOWN
        case 7: key = .mute              // NX_KEYTYPE_MUTE
        default: return nil
        }
        isDown = state == 0xA
        isRepeat = flags & 0x1 != 0
    }
}

/// Intercepts the volume and brightness keys so Notchi's HUD replaces the system's.
///
/// An active event tap (needs Accessibility) sees each special-key event before the system does.
/// When the handler takes a key, the press and its release are swallowed, so the system HUD never
/// appears. Keys the handler declines (an output without volume control, an external monitor)
/// pass through untouched, as does ⌥ alone (the system shortcut that opens Sound or Displays
/// settings). If Notchi quits or crashes, the tap goes with it and the keys return to the system.
@MainActor
final class MediaKeyInterceptor {
    /// Return true to take the key (swallow it), false to let the system handle it.
    var handler: ((MediaKeyEvent.Key, _ fine: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Keys whose press was taken, so their release is swallowed too.
    private var takenKeys: Set<Int> = []

    var isRunning: Bool { tap != nil }

    /// Starts intercepting. Fails (returns false) without Accessibility permission.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let systemDefined = CGEventMask(1 << 14)  // NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(context).takeUnretainedValue()
            // The tap's source is on the main run loop, so this runs on the main thread.
            let swallow = MainActor.assumeIsolated { interceptor.shouldSwallow(type: type, event: event) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: systemDefined, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        takenKeys.removeAll()
    }

    private func shouldSwallow(type: CGEventType, event: CGEvent) -> Bool {
        // macOS disables slow or interrupted taps; turn it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8,
              let keyEvent = MediaKeyEvent(data1: nsEvent.data1)
        else { return false }

        let keyID = (nsEvent.data1 & 0xFFFF_0000) >> 16
        guard keyEvent.isDown else {
            return takenKeys.remove(keyID) != nil
        }

        let flags = event.flags
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        // ⌥ alone opens Sound/Displays settings: leave that to the system.
        if option && !shift { return false }

        let taken = handler?(keyEvent.key, option && shift) ?? false
        if taken { takenKeys.insert(keyID) }
        return taken
    }
}
