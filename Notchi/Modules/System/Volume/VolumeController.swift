import AudioToolbox
import CoreAudio
import Foundation

/// Output volume and mute state.
struct VolumeState: Equatable, Sendable {
    /// 0…1.
    var level: Double
    var isMuted: Bool
    /// False for outputs without software volume (some HDMI and USB devices).
    var canChange: Bool

    /// What the HUD shows: muted reads as zero.
    var effectiveLevel: Double { isMuted ? 0 : level }
}

/// Reads and sets the default output device's volume, and reports every change, wherever it came
/// from (keys, Control Center, AirPods buttons, another app). Follows the default output device
/// when it switches.
@MainActor
final class VolumeController {
    var onChange: ((VolumeState) -> Void)?
    private(set) var state = VolumeState(level: 0, isMuted: false, canChange: false)

    private var deviceID = AudioDeviceID(kAudioObjectUnknown)
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard defaultDeviceListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.bindDefaultDevice() }
        }
        defaultDeviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main, listener)
        bindDefaultDevice()
    }

    func stop() {
        unbindDevice()
        if let defaultDeviceListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main, defaultDeviceListener)
        }
        defaultDeviceListener = nil
    }

    /// Sets the level (0…1). Unmutes when raising from mute, like the system does.
    func setLevel(_ level: Double) {
        guard deviceID != kAudioObjectUnknown else { return }
        var value = Float32(min(max(level, 0), 1))
        AudioObjectSetPropertyData(deviceID, &Self.volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if state.isMuted && level > 0 { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        guard deviceID != kAudioObjectUnknown else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: Device binding

    private func bindDefaultDevice() {
        unbindDevice()
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, 0, nil, &size, &id)
        deviceID = id
        guard id != kAudioObjectUnknown else { return }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(id, &Self.volumeAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(id, &Self.muteAddress, .main, listener)
        refresh()
    }

    private func unbindDevice() {
        if deviceID != kAudioObjectUnknown, let deviceListener {
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.volumeAddress, .main, deviceListener)
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.muteAddress, .main, deviceListener)
        }
        deviceListener = nil
        deviceID = AudioDeviceID(kAudioObjectUnknown)
    }

    private func refresh() {
        let newState = read()
        guard newState != state else { return }
        state = newState
        onChange?(newState)
    }

    private func read() -> VolumeState {
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let hasVolume = AudioObjectHasProperty(deviceID, &Self.volumeAddress)
        if hasVolume { AudioObjectGetPropertyData(deviceID, &Self.volumeAddress, 0, nil, &size, &level) }

        var settable: DarwinBoolean = false
        if hasVolume { AudioObjectIsPropertySettable(deviceID, &Self.volumeAddress, &settable) }

        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(deviceID, &Self.muteAddress) {
            AudioObjectGetPropertyData(deviceID, &Self.muteAddress, 0, nil, &size, &muted)
        }
        return VolumeState(level: Double(level), isMuted: muted != 0, canChange: hasVolume && settable.boolValue)
    }
}

/// Volume and brightness keys move in 16 steps, or 64 with ⌥⇧, snapping to the grid like macOS.
enum LevelStep {
    static func next(from level: Double, up: Bool, fine: Bool) -> Double {
        let steps = fine ? 64.0 : 16.0
        let current = (level * steps).rounded()
        return min(max((current + (up ? 1 : -1)) / steps, 0), 1)
    }
}
