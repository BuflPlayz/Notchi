import Foundation

/// Now playing for every app (Music, Spotify, browsers, podcasts…) through the system's
/// MediaRemote service.
///
/// Since macOS 15.4, MediaRemote only answers callers with an Apple bundle ID. The vendored
/// mediaremote-adapter runs under `/usr/bin/perl` (which is `com.apple.perl`) and loads a small
/// framework that streams changes as JSON lines. This class runs that stream, parses it off the
/// main thread, and sends transport commands through one-shot invocations of the same tool.
@MainActor
final class MediaRemoteAdapterProvider: NowPlayingProvider {
    /// Where the adapter lives inside the app bundle.
    struct Location: Sendable {
        let script: URL
        let framework: URL

        /// The copy embedded in `Notchi.app/Contents/Frameworks`, or nil if missing.
        static var bundled: Location? {
            guard
                let framework = Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
                let script = Bundle(url: framework)?.url(forResource: "mediaremote-adapter", withExtension: "pl")
            else { return nil }
            return Location(script: script, framework: framework)
        }
    }

    var onUpdate: ((NowPlayingInfo?) -> Void)?
    let sourceName = "System Now Playing (all apps)"

    private let location: Location
    private var process: Process?
    private var readTask: Task<Void, Never>?
    private var isRunning = false
    private var restartAttempts = 0

    init(location: Location) {
        self.location = location
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        terminateOrphanedStreams()
        launchStream()
    }

    func stop() {
        isRunning = false
        readTask?.cancel()
        readTask = nil
        process?.terminate()
        process = nil
    }

    func send(_ command: MediaCommand) {
        var arguments = [location.script.path, location.framework.path]
        switch command {
        case .seek(let position):
            arguments += ["seek", String(Int((position * 1_000_000).rounded()))]
        default:
            arguments += ["send", String(Self.commandID(for: command))]
        }
        run(arguments: arguments)
    }

    // MARK: Stream

    private func launchStream() {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // Diffs keep artwork (hundreds of KB of base64) from being re-sent on every play/pause.
        process.arguments = [location.script.path, location.framework.path, "stream", "--micros", "--debounce=50"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.streamEnded() }
        }
        do {
            try process.run()
        } catch {
            streamEnded()
            return
        }
        self.process = process

        let output = pipe.fileHandleForReading
        readTask = Task.detached(priority: .utility) { [weak self] in
            var parser = AdapterStreamParser()
            do {
                for try await line in output.bytes.lines {
                    guard case .update(let info) = parser.consume(line) else { continue }
                    await self?.deliver(info)
                }
            } catch {
                // Pipe closed: the termination handler takes it from here.
            }
        }
    }

    private func deliver(_ info: NowPlayingInfo?) {
        restartAttempts = 0
        onUpdate?(info)
    }

    /// Restarts a stream that died unexpectedly, backing off, and gives up after a few tries.
    private func streamEnded() {
        process = nil
        guard isRunning, restartAttempts < 5 else { return }
        restartAttempts += 1
        let delay = Double(restartAttempts)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.isRunning, self.process == nil else { return }
            self.launchStream()
        }
    }

    /// If Notchi crashed, its stream outlived it (reparented to launchd). Remove those leftovers:
    /// only streams of this very adapter whose parent is gone.
    private func terminateOrphanedStreams() {
        run(executable: "/usr/bin/pkill", arguments: ["-P", "1", "-f", "\(location.framework.path) stream"])
    }

    // MARK: Commands

    private func run(executable: String = "/usr/bin/perl", arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// MRCommand IDs from the adapter's `src/private/MediaRemote.h`.
    private static func commandID(for command: MediaCommand) -> Int {
        switch command {
        case .play: 0
        case .pause: 1
        case .togglePlayPause: 2
        case .nextTrack: 4
        case .previousTrack: 5
        case .seek: -1
        }
    }
}
