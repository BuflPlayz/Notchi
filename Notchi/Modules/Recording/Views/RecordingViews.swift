import SwiftUI

/// The iPhone's microphone-in-use orange.
private let audioOrange = Color.orange

// MARK: - Compact

/// A pulsing red dot while the screen records, an orange mic while an app records audio. Also the
/// bubble beside the notch.
struct RecordingGlyph: View {
    let module: CaptureModule

    var body: some View {
        Group {
            if module.screenSince != nil {
                LayerSymbol(name: "record.circle.fill", style: AnyShapeStyle(callRed), styleKey: "record.red", size: 14, pulses: true)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(audioOrange)
            }
        }
        .notchMatchedGeometry(id: "recording.glyph")
    }
}

/// Left slot, pinned to the outer edge like the HUD's icon.
struct RecordingCompactLeading: View {
    let module: CaptureModule

    var body: some View {
        RecordingGlyph(module: module)
            .hudSlot(.leading)
    }
}

/// Right slot: how long it has been recording, counted by SwiftUI itself.
struct RecordingCompactTrailing: View {
    let module: CaptureModule

    var body: some View {
        Group {
            if let since = module.screenSince ?? module.audio?.since {
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
            }
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(module.screenSince != nil ? callRed : audioOrange)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .hudSlot(.trailing)
    }
}

// MARK: - Expanded

/// What's recording, for how long, and a way to stop it (the screen) or find it (an app).
struct RecordingExpandedView: View {
    let module: CaptureModule

    var body: some View {
        VStack(spacing: 10) {
            if let since = module.screenSince {
                row(
                    icon: AnyView(symbolTile("record.circle.fill", color: callRed)),
                    title: "Screen Recording",
                    subtitle: "The screen is being recorded or shared",
                    since: since,
                    color: callRed
                ) {
                    if module.canStopScreen {
                        Button(action: module.stopScreenRecording) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(NotchButtonStyle())
                    }
                }
            }
            if let audio = module.audio {
                row(
                    icon: AnyView(AppIconView(bundleID: audio.appBundleID, size: 34)),
                    title: audio.appName,
                    subtitle: "Recording from the microphone",
                    since: audio.since,
                    color: audioOrange
                ) {
                    if audio.appBundleID != nil {
                        Button("Show", action: module.showAudioApp)
                            .buttonStyle(NotchButtonStyle())
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(icon: AnyView, title: String, subtitle: String, since: Date, color: Color, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                .font(.system(size: 24, weight: .light).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            action()
        }
    }

    private func symbolTile(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.controlFill))
    }
}

// MARK: - Settings

/// Settings › Recording.
struct RecordingSettingsView: View {
    let module: CaptureModule

    @AppStorage(Preferences.Key.recordingShowsScreen) private var showsScreen = true
    @AppStorage(Preferences.Key.recordingShowsMicrophone) private var showsMicrophone = true
    @Environment(\.moduleRegistry) private var registry

    private var isEnabled: Bool { registry?.modules.contains { $0.id == module.id } ?? true }

    var body: some View {
        if registry != nil {
            Section {
                ModuleEnabledToggle(moduleID: module.id, title: "Show recordings in the notch")
            }
        }

        Section {
            Toggle("Screen recording and sharing", isOn: $showsScreen)
                .disabled(!ScreenCaptureMonitor.isAvailable)
            Toggle("Apps recording from the microphone", isOn: $showsMicrophone)
        } header: {
            Text("Recording")
        } footer: {
            SettingsFootnote("While the screen is recorded or shared, a red dot and the time show beside the notch; a recording from the Screenshot toolbar (⇧⌘5) can be stopped from the open notch. Apps recording audio, like Voice Memos, show an orange microphone. Calls are under Calls.")
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Previews

#Preview("Expanded · screen + audio") {
    let module = CaptureModule()
    module.applyScreen(true)
    return RecordingExpandedView(module: module)
        .frame(width: 408, height: 126)
        .padding()
        .background(Theme.surface)
        .foregroundStyle(Theme.primary)
}
