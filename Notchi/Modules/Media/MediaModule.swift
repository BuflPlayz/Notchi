import AppKit
import SwiftUI

/// Now playing in the notch: artwork and a visualizer while music plays (compact), and the full
/// player with progress and controls when opened (expanded).
@MainActor
@Observable
final class MediaModule: NotchModule {
    let id = "media"
    let title = "Now Playing"
    let symbol = "music.note"

    private(set) var info: NowPlayingInfo?
    private(set) var artwork: NSImage?
    /// Accent derived from the artwork; white when there's no artwork or it's grayscale.
    private(set) var accent: Color = Theme.primary
    private(set) var liveActivity: LiveActivity?

    @ObservationIgnored private let provider: NowPlayingProvider
    /// Real audio levels for the visualizer; nil in previews and tests (synthetic bars).
    @ObservationIgnored let audioMonitor: AudioLevelMonitor?
    @ObservationIgnored private let pauseLinger: Duration
    @ObservationIgnored private var lingerTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    /// Last report from the provider, before filtering by source app.
    @ObservationIgnored private var latestReport: NowPlayingInfo?
    @ObservationIgnored private var preferencesObserver: NSObjectProtocol?
    @ObservationIgnored private var showsAllSources = Preferences.showAllMediaSources

    /// - Parameter pauseLinger: How long compact mode stays after pausing. It also absorbs the brief
    ///   pause some players report between tracks, so the notch doesn't flicker on a track change.
    init(provider: NowPlayingProvider, audioMonitor: AudioLevelMonitor? = nil, pauseLinger: Duration = .seconds(2.5)) {
        self.provider = provider
        self.audioMonitor = audioMonitor
        self.pauseLinger = pauseLinger
    }

    func start() {
        provider.onUpdate = { [weak self] info in
            self?.latestReport = info
            self?.apply(Self.filtered(info))
        }
        provider.start()
        // Re-apply the source filter when its setting changes.
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateAudioCapture()
                guard self.showsAllSources != Preferences.showAllMediaSources else { return }
                self.showsAllSources = Preferences.showAllMediaSources
                self.apply(Self.filtered(self.latestReport))
            }
        }
    }

    /// Hides media from apps that aren't music apps (unless the user opted into all sources).
    private static func filtered(_ info: NowPlayingInfo?) -> NowPlayingInfo? {
        guard let info, MediaSourceFilter.allows(info.sourceBundleIdentifier) else { return nil }
        return info
    }

    func stop() {
        provider.stop()
        audioMonitor?.stop()
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
    }

    func perform(_ command: MediaCommand) {
        // Reflect the change immediately; the provider's next update confirms it.
        if var predicted = info {
            predicted.elapsed = predicted.elapsed(at: Date())
            predicted.timestamp = Date()
            switch command {
            case .play: predicted.isPlaying = true
            case .pause: predicted.isPlaying = false
            case .togglePlayPause: predicted.isPlaying.toggle()
            case .seek(let position): predicted.elapsed = position
            case .nextTrack, .previousTrack: break
            }
            apply(predicted)
        }
        provider.send(command)
    }

    /// Where now-playing information comes from (shown in Settings).
    var sourceName: String { provider.sourceName }

    /// Brings the app that's playing to the front.
    func openSourceApp() {
        guard let bundleID = info?.sourceBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: NotchModule views

    func compactLeading() -> AnyView {
        AnyView(
            MediaArtworkView(image: artwork, size: 22, cornerRadius: 6)
                .notchMatchedGeometry(id: "media.artwork")
        )
    }

    func compactTrailing() -> AnyView {
        AnyView(MediaVisualizer(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(MediaSettingsView(module: self))
    }

    func expandedView() -> AnyView {
        AnyView(ExpandedMediaView(module: self))
    }

    // MARK: State

    private func apply(_ newInfo: NowPlayingInfo?) {
        let previous = info
        info = newInfo

        if newInfo?.artworkData != previous?.artworkData {
            // Artwork often arrives a moment after the track; keep the current image until then.
            let artworkStillLoading = newInfo?.artworkData == nil && newInfo?.isSameTrack(as: previous) == true
            if !artworkStillLoading { loadArtwork(newInfo?.artworkData) }
        }
        updateLiveActivity()
        updateAudioCapture()
    }

    /// The audio tap (and the system's recording indicator) only runs while music plays.
    private func updateAudioCapture() {
        guard let audioMonitor else { return }
        if info?.isPlaying == true && Preferences.realAudioVisualizer {
            audioMonitor.start()
        } else {
            audioMonitor.stop()
        }
    }

    private func updateLiveActivity() {
        if info?.isPlaying == true {
            lingerTask?.cancel()
            lingerTask = nil
            if liveActivity == nil { liveActivity = LiveActivity(priority: .active) }
        } else if liveActivity != nil, lingerTask == nil {
            let linger = pauseLinger
            lingerTask = Task { [weak self] in
                try? await Task.sleep(for: linger)
                guard let self, !Task.isCancelled else { return }
                self.lingerTask = nil
                if self.info?.isPlaying != true { self.liveActivity = nil }
            }
        }
    }

    /// Decodes artwork and its accent color off the main actor.
    private func loadArtwork(_ data: Data?) {
        artworkTask?.cancel()
        guard let data else {
            withAnimation(Motion.content) {
                artwork = nil
                accent = Theme.primary
            }
            return
        }
        artworkTask = Task { [weak self] in
            let decoded = await Task.detached(priority: .utility) { ArtworkPalette.decode(data) }.value
            guard let self, !Task.isCancelled else { return }
            withAnimation(Motion.content) {
                self.artwork = decoded.map { NSImage(cgImage: $0.image, size: .zero) }
                self.accent = decoded?.accent.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) } ?? Theme.primary
            }
        }
    }
}

/// Compact visualizer that reads the audio levels itself, so the ~30 updates a second re-render
/// only these bars, not the artwork and the rest of the compact notch.
private struct MediaVisualizer: View {
    let module: MediaModule

    var body: some View {
        AudioVisualizerView(
            isPlaying: module.info?.isPlaying == true,
            color: module.accent,
            levels: module.audioMonitor?.displayLevels
        )
    }
}
