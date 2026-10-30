import CoreGraphics
import Foundation

/// Display brightness through the private DisplayServices framework (what the brightness keys use).
///
/// Loaded with `dlopen`, so nothing breaks if a future macOS removes it: `isAvailable` turns false
/// and the keys go back to the system. Works for the built-in display and Apple displays. Other
/// external monitors (DDC/CI) report `canChange == false`.
@MainActor
final class BrightnessController {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool

    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private let canChangeBrightness: CanChangeBrightness?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        getBrightness = symbol("DisplayServicesGetBrightness", as: GetBrightness.self)
        setBrightness = symbol("DisplayServicesSetBrightness", as: SetBrightness.self)
        canChangeBrightness = symbol("DisplayServicesCanChangeBrightness", as: CanChangeBrightness.self)
    }

    var isAvailable: Bool { getBrightness != nil && setBrightness != nil }

    /// The display the brightness keys control: the built-in one if present, otherwise the main display.
    var targetDisplay: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    var canChange: Bool {
        guard isAvailable else { return false }
        return canChangeBrightness?(targetDisplay) ?? true
    }

    /// 0…1, or nil when unavailable.
    var level: Double? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(targetDisplay, &value) == 0 else { return nil }
        return Double(value)
    }

    @discardableResult
    func setLevel(_ level: Double) -> Bool {
        guard let setBrightness, canChange else { return false }
        return setBrightness(targetDisplay, Float(min(max(level, 0), 1))) == 0
    }
}
