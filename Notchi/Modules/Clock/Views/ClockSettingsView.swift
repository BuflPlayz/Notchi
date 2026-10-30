import SwiftUI

/// Settings › Clock.
struct ClockSettingsView: View {
    let module: ClockModule

    @AppStorage(Preferences.Key.clockShowsPaused) private var showsPaused = true

    var body: some View {
        Section {
            Toggle("Show paused timers and stopwatch", isOn: $showsPaused)
            LabeledContent("Right now", value: status)
        } header: {
            Text("Clock App")
        } footer: {
            SettingsFootnote("Notchi shows the timers and stopwatch you start in Apple's Clock app. They're started, paused and reset in Clock; clicking them in the notch opens it. Running timers always show; paused ones are optional.")
        }

        Section {
            Button("Open Clock", action: module.openClockApp)
        }
    }

    private var status: String {
        let running = module.snapshot.timers.filter(\.isRunning).count
        let paused = module.snapshot.timers.count - running
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if paused > 0 { parts.append("\(paused) paused") }
        var summary = parts.isEmpty ? "No timers" : parts.joined(separator: ", ") + (module.snapshot.timers.count == 1 ? " timer" : " timers")
        if let stopwatch = module.snapshot.stopwatch {
            summary += stopwatch.isRunning ? " · stopwatch running" : " · stopwatch paused"
        }
        return summary
    }
}

#Preview("Clock settings") {
    let module = ClockModule(provider: MockClockProvider())
    module.start()
    return SettingsPane { ClockSettingsView(module: module) }
        .frame(width: 500)
}
