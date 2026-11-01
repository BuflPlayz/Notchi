import CoreServices
import Foundation

/// Watches folders, recursively, with FSEvents and reports the files that changed in batches.
///
/// Event-driven: nothing runs while the agents are quiet. Batches arrive on a private queue, a
/// fraction of a second after the writes (FSEvents coalesces bursts).
final class FileEventStream: @unchecked Sendable {
    private let paths: [String]
    private let latency: CFTimeInterval
    private let onChange: @Sendable ([String]) -> Void
    private let queue = DispatchQueue(label: "dev.notchi.agents.file-events")
    /// Only touched from `start`/`stop`, which the owner calls from the main actor.
    private var stream: FSEventStreamRef?

    init(paths: [String], latency: CFTimeInterval = 0.15, onChange: @escaping @Sendable ([String]) -> Void) {
        self.paths = paths
        self.latency = latency
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        // FSEvents ignores folders that don't exist yet; agents that were never run aren't watched.
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard stream == nil, !existing.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let stream = Unmanaged<FileEventStream>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            stream.onChange(paths)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            nil, callback, &context, existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
