import SwiftUI

// MARK: - Compact

/// The Focus's symbol in its color (dimmed once it's off), bouncing when it turns on or off. Also
/// the bubble beside the notch.
struct FocusGlyph: View {
    let module: FocusModule

    var body: some View {
        let style = module.style
        Image(systemName: module.state.isActive || module.isAnnouncing ? style.symbol : "moon")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(module.state.isActive ? style.color : Theme.secondary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: module.state.isActive)
    }
}

/// Left slot, pinned to the outer edge like the HUD's icon: the symbol, and while announcing a
/// change, the Focus's name after it.
struct FocusCompactLeading: View {
    let module: FocusModule

    var body: some View {
        HStack(spacing: 7) {
            FocusGlyph(module: module)
            if module.isAnnouncing {
                Text(module.announcedName ?? "Focus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(module.state.isActive ? Theme.primary : Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .hudSlot(.leading)
    }
}

/// Right slot: "On" / "Off" while announcing a change; for a Focus that stays in the notch, its name.
struct FocusCompactTrailing: View {
    let module: FocusModule

    var body: some View {
        let style = module.style
        let label = module.isAnnouncing ? (module.state.isActive ? "On" : "Off") : style.label
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(module.state.isActive ? style.color : Theme.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.interpolate)
            .hudSlot(.trailing)
    }
}

// MARK: - Settings

/// Settings › Focus.
struct FocusSettingsView: View {
    let module: FocusModule

    @AppStorage(Preferences.Key.focusActivity) private var focusActivity = false
    @AppStorage(Preferences.Key.focusAlerts) private var focusAlerts = true

    var body: some View {
        Section {
            Toggle("Announce when a Focus turns on or off", isOn: $focusAlerts)
            Toggle("Keep an active Focus in the notch", isOn: $focusActivity)
            LabeledContent("Accessibility") {
                if module.permission.isGranted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Button("Allow…", action: module.requestAccessibility)
                        Button("Open Settings…", action: module.permission.openSettings)
                    }
                }
            }
        } header: {
            Text("Focus")
        } footer: {
            SettingsFootnote("Turning a Focus on or off shows in the notch for a few seconds, unless something else is showing or the notch is open. Kept in the notch, an active Focus also stays beside it, or in it when nothing else is running. Notchi sees Focus through Control Center's Focus menu bar item (Settings › Control Center › Focus › Show When Active), which needs Accessibility.")
        }
    }
}
