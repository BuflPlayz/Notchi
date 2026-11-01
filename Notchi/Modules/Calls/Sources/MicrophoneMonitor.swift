import AppKit
import CoreAudio

/// An app recording from a microphone right now.
struct MicrophoneUse: Equatable, Sendable {
    /// The app responsible for the recording: the browser for its helper process, the app for its
    /// XPC service. The recording process itself for daemons with no app.
    let pid: pid_t
    /// Nil for daemons with no bundle.
    let bundleID: String?
    /// The process's executable name, for daemons like `avconferenced`.
    let processName: String
    /// When Notchi first saw it recording.
    let since: Date
}

/// Which apps are recording from a microphone, from Core Audio's process list (macOS 14+, no permission).
///
/// Core Audio announces a recording that starts: the process list changes (a new client), a
/// process's device list changes, or an input device starts running. It doesn't announce one that
/// stops (measured on macOS 27.2: no `IsRunningInput` or `IsRunning` notification fired), so while
/// anything records, the monitor also reads the list once a second, about 20 property reads. With
/// nothing recording it never polls.
///
/// Notchi itself is left out: the visualizer's system audio tap counts as input.
@MainActor
final class MicrophoneMonitor {
    var onChange: (([MicrophoneUse]) -> Void)?
    /// Also called on every check while something records, so users can refresh what they derive.
    var onTick: (() -> Void)?
    private(set) var uses: [MicrophoneUse] = []

    private var systemListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var deviceListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var pollTimer: Timer?
    private var burstTask: Task<Void, Never>?

    private static var processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var processDevicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyDevices,
        mScope: kAudioObjectPropertyScopeWildcard,
        mElement: kAudioObjectPropertyElementWildcard
    )
    private static var runningSomewhereAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeWildcard,
        mElement: kAudioObjectPropertyElementWildcard
    )

    func start() {
        guard systemListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.bindObjects()
                self?.refreshBurst()
            }
        }
        systemListener = listener
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListenerBlock(system, &Self.processListAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(system, &Self.devicesAddress, .main, listener)
        bindObjects()
        refresh()
    }

    func stop() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if let systemListener {
            AudioObjectRemovePropertyListenerBlock(system, &Self.processListAddress, .main, systemListener)
            AudioObjectRemovePropertyListenerBlock(system, &Self.devicesAddress, .main, systemListener)
        }
        systemListener = nil
        for (id, listener) in processListeners {
            AudioObjectRemovePropertyListenerBlock(id, &Self.processDevicesAddress, .main, listener)
        }
        processListeners = [:]
        for (id, listener) in deviceListeners {
            AudioObjectRemovePropertyListenerBlock(id, &Self.runningSomewhereAddress, .main, listener)
        }
        deviceListeners = [:]
        pollTimer?.invalidate()
        pollTimer = nil
        burstTask?.cancel()
        burstTask = nil
        uses = []
    }

    // MARK: Listening

    /// Listens to every audio client and every input device, dropping the ones that went away.
    private func bindObjects() {
        let processes = Set(Self.objectList(Self.processListAddress))
        for (id, listener) in processListeners where !processes.contains(id) {
            AudioObjectRemovePropertyListenerBlock(id, &Self.processDevicesAddress, .main, listener)
            processListeners[id] = nil
        }
        for id in processes where processListeners[id] == nil {
            let listener = changeListener()
            AudioObjectAddPropertyListenerBlock(id, &Self.processDevicesAddress, .main, listener)
            processListeners[id] = listener
        }

        let devices = Set(Self.objectList(Self.devicesAddress).filter(Self.hasInput))
        for (id, listener) in deviceListeners where !devices.contains(id) {
            AudioObjectRemovePropertyListenerBlock(id, &Self.runningSomewhereAddress, .main, listener)
            deviceListeners[id] = nil
        }
        for id in devices where deviceListeners[id] == nil {
            let listener = changeListener()
            AudioObjectAddPropertyListenerBlock(id, &Self.runningSomewhereAddress, .main, listener)
            deviceListeners[id] = listener
        }
    }

    private func changeListener() -> AudioObjectPropertyListenerBlock {
        { [weak self] _, _ in MainActor.assumeIsolated { self?.refreshBurst() } }
    }

    /// Reads now and a moment later: a new client starts its input shortly after it registers.
    private func refreshBurst() {
        refresh()
        burstTask?.cancel()
        burstTask = Task { [weak self] in
            for delay in [Duration.milliseconds(150), .milliseconds(500)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    private func refresh() {
        let previous = Dictionary(uniqueKeysWithValues: uses.map { ($0.pid, $0.since) })
        let now = Date()
        var seen = Set<pid_t>()
        var current: [MicrophoneUse] = []
        for id in Self.objectList(Self.processListAddress) where Self.uInt32(id, kAudioProcessPropertyIsRunningInput) != 0 {
            let processID: pid_t = Self.value(id, kAudioProcessPropertyPID) ?? -1
            guard processID > 0, processID != getpid() else { continue }
            let owner = Self.responsibleApp(for: processID)
            let pid = owner?.processIdentifier ?? processID
            guard pid != getpid(), seen.insert(pid).inserted else { continue }
            let bundleID = owner?.bundleIdentifier ?? Self.string(id, kAudioProcessPropertyBundleID)
            current.append(MicrophoneUse(pid: pid, bundleID: bundleID, processName: Self.processName(processID), since: previous[pid] ?? now))
        }
        current.sort { $0.since < $1.since }
        updatePolling(recording: !current.isEmpty)
        onTick?()
        guard current != uses else { return }
        uses = current
        onChange?(current)
    }

    private func updatePolling(recording: Bool) {
        if recording, pollTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 0.3
            pollTimer = timer
        } else if !recording {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    // MARK: Processes

    /// The app a process records for: a browser's helper or an app's XPC service belongs to the app
    /// that launched it, which macOS tracks as the "responsible" process.
    private static func responsibleApp(for pid: pid_t) -> NSRunningApplication? {
        if let responsible = responsiblePID?(pid), responsible > 0,
           let app = NSRunningApplication(processIdentifier: responsible), app.bundleIdentifier != nil {
            return app
        }
        return NSRunningApplication(processIdentifier: pid).flatMap { $0.bundleIdentifier == nil ? nil : $0 }
    }

    /// `responsibility_get_pid_responsible_for_pid`, private in libSystem, looked up once.
    private static let responsiblePID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        return String(cString: buffer)
    }

    // MARK: Core Audio

    private static func objectList(_ address: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var address = address
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func hasInput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func uInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        value(object, selector) ?? 0
    }

    private static func value<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String?, !string.isEmpty
        else { return nil }
        return string
    }
}

/// The default input device's mute switch: the system-wide microphone mute.
@MainActor
final class MicrophoneMute {
    /// Mute turned on or off, or the default input changed.
    var onChange: (() -> Void)?
    private(set) var isMuted = false
    /// False for inputs without a mute control.
    private(set) var canMute = false

    private var deviceID = AudioDeviceID(kAudioObjectUnknown)
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?

    private static var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard defaultDeviceListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.bindDefaultDevice() }
        }
        defaultDeviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultInputAddress, .main, listener)
        bindDefaultDevice()
    }

    func stop() {
        unbindDevice()
        if let defaultDeviceListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultInputAddress, .main, defaultDeviceListener)
        }
        defaultDeviceListener = nil
    }

    func setMuted(_ muted: Bool) {
        guard canMute else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func bindDefaultDevice() {
        unbindDevice()
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultInputAddress, 0, nil, &size, &device)
        deviceID = device
        var settable: DarwinBoolean = false
        canMute = device != kAudioObjectUnknown
            && AudioObjectHasProperty(device, &Self.muteAddress)
            && AudioObjectIsPropertySettable(device, &Self.muteAddress, &settable) == noErr && settable.boolValue
        if canMute {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.read() }
            }
            muteListener = listener
            AudioObjectAddPropertyListenerBlock(device, &Self.muteAddress, .main, listener)
        }
        read()
        onChange?()
    }

    private func unbindDevice() {
        if let muteListener, deviceID != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.muteAddress, .main, muteListener)
        }
        muteListener = nil
        deviceID = AudioDeviceID(kAudioObjectUnknown)
    }

    private func read() {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let muted = canMute && AudioObjectGetPropertyData(deviceID, &Self.muteAddress, 0, nil, &size, &value) == noErr && value != 0
        guard muted != isMuted else { return }
        isMuted = muted
        onChange?()
    }
}
