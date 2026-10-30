import AudioToolbox
import CoreAudio
import Foundation

/// Captures what the Mac is playing, without affecting it, and reports visualizer band levels.
///
/// A Core Audio process tap (macOS 14.2+) on the system output, excluding nobody, is wrapped in a
/// private aggregate device whose IO block runs `SpectrumAnalyzer` on a dedicated queue. The
/// first start triggers the "System Audio Recording Only" permission prompt, and macOS shows its
/// recording indicator while the tap runs. If permission is denied, the tap delivers silence.
@available(macOS 14.2, *)
final class SystemAudioTap: @unchecked Sendable {
    enum TapError: Error, CustomStringConvertible {
        case coreAudio(step: String, status: OSStatus)

        var description: String {
            switch self {
            case .coreAudio(let step, let status): "Core Audio failed to \(step) (\(status))"
            }
        }
    }

    // Only touched from start()/stop() on the main actor; the IO block only touches the analyzer.
    private let queue = DispatchQueue(label: "dev.notchi.audio-tap", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    /// Starts capturing. `onLevels` is called on the audio queue about 30 times a second.
    func start(bandCount: Int, onLevels: @escaping @Sendable ([Float]) -> Void) throws {
        do {
            try startCapture(bandCount: bandCount, onLevels: onLevels)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    // MARK: Setup

    private func startCapture(bandCount: Int, onLevels: @escaping @Sendable ([Float]) -> Void) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Notchi Visualizer"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check("create the audio tap", AudioHardwareCreateProcessTap(description, &tapID))

        let format = try tapFormat()
        let outputUID = try defaultOutputDeviceUID()
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notchi Visualizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check("create the aggregate device", AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregateID))

        let analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate, bandCount: bandCount)
        let mixer = MonoMixer(channels: Int(max(format.mChannelsPerFrame, 1)))
        try check("create the IO callback", AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, input, _, _, _ in
            mixer.mix(input) { samples in
                if let levels = analyzer.process(samples) { onLevels(levels) }
            }
        })
        try check("start capturing", AudioDeviceStart(aggregateID, ioProcID))
    }

    private func tapFormat() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check("read the tap format", AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format))
        return format
    }

    private func defaultOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check("find the output device", AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID))

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check("read the output device", AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid))
        guard let uid else { throw TapError.coreAudio(step: "read the output device", status: -1) }
        return uid.takeRetainedValue() as String
    }

    private func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw TapError.coreAudio(step: step, status: status) }
    }
}

/// Mixes an incoming buffer list (interleaved or not) down to mono, into a reused buffer.
private final class MonoMixer {
    private let channels: Int
    private var mono: [Float] = []

    init(channels: Int) {
        self.channels = channels
    }

    func mix(_ input: UnsafePointer<AudioBufferList>, _ body: (UnsafeBufferPointer<Float>) -> Void) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let firstData = first.mData else { return }

        if buffers.count == 1 {
            // One buffer: interleaved frames (or plain mono).
            let channelCount = max(Int(first.mNumberChannels), 1)
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channelCount
            let samples = firstData.assumingMemoryBound(to: Float.self)
            if channelCount == 1 {
                body(UnsafeBufferPointer(start: samples, count: frames))
                return
            }
            ensureCapacity(frames)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channelCount { sum += samples[frame * channelCount + channel] }
                mono[frame] = sum / Float(channelCount)
            }
            mono.withUnsafeBufferPointer { body(UnsafeBufferPointer(rebasing: $0[0..<frames])) }
        } else {
            // One buffer per channel.
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            ensureCapacity(frames)
            for index in 0..<frames { mono[index] = 0 }
            var used = 0
            for buffer in buffers {
                guard let data = buffer.mData, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size >= frames else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<frames { mono[index] += samples[index] }
                used += 1
            }
            guard used > 0 else { return }
            let scale = 1 / Float(used)
            for index in 0..<frames { mono[index] *= scale }
            mono.withUnsafeBufferPointer { body(UnsafeBufferPointer(rebasing: $0[0..<frames])) }
        }
    }

    private func ensureCapacity(_ frames: Int) {
        if mono.count < frames { mono = Array(repeating: 0, count: frames) }
    }
}
