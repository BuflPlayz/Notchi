import SwiftUI

/// Settings › Now Playing.
struct MediaSettingsView: View {
    let module: MediaModule

    @AppStorage(Preferences.Key.realAudioVisualizer) private var realAudioVisualizer = true
    @AppStorage(Preferences.Key.showAllMediaSources) private var showAllMediaSources = false

    var body: some View {
        Section {
            Toggle("Show media from browsers and video apps", isOn: $showAllMediaSources)
            LabeledContent("Source", value: module.sourceName)
        } header: {
            Text("Sources")
        } footer: {
            SettingsFootnote("By default only music apps appear: \(Self.musicAppNames). Turn this on to include YouTube and other browser or video media.")
        }

        Section {
            Toggle("Visualizer follows the music", isOn: $realAudioVisualizer)
        } header: {
            Text("Visualizer")
        } footer: {
            SettingsFootnote("Listens to what your Mac plays, only while music plays, to move the bars. macOS asks for permission once and shows its recording indicator meanwhile. Nothing is recorded or saved. Off: the bars use a gentle animation instead.")
        }
    }

    private static var musicAppNames: String {
        let names = MediaSourceFilter.musicApps.compactMap { bundleID -> String? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return names.isEmpty ? "Music and Spotify" : names.sorted().formatted(.list(type: .and))
    }
}

#Preview("Media settings") {
    SettingsPane { MediaSettingsView(module: MediaModule(provider: MockNowPlayingProvider())) }
        .frame(width: 500)
}
