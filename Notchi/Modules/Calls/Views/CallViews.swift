import SwiftUI

/// The iPhone's call green, and its "end call" red.
let callGreen = Color(red: 0.2, green: 0.84, blue: 0.29)
let callRed = Color(red: 1, green: 0.27, blue: 0.23)

// MARK: - Compact

/// A phone ringing (pulsing), a call on (a camera for video, a crossed-out mic when muted), or the
/// hung-up phone after it ends. Also the bubble beside the notch.
struct CallGlyph: View {
    let module: CallsModule

    var body: some View {
        Group {
            if module.incoming != nil {
                LayerSymbol(name: "phone.fill", style: AnyShapeStyle(callGreen), styleKey: "call.green", size: 15, pulses: true)
            } else if module.ended != nil && module.call == nil {
                Image(systemName: "phone.down.fill")
                    .foregroundStyle(callRed)
            } else if module.isMicrophoneMuted {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(callRed)
            } else {
                Image(systemName: module.call?.isVideo == true ? "video.fill" : "phone.fill")
                    .foregroundStyle(callGreen)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .contentTransition(.symbolEffect(.replace))
        .notchMatchedGeometry(id: "calls.glyph")
    }
}

/// Left slot, pinned to the outer edge like the HUD's icon.
struct CallCompactLeading: View {
    let module: CallsModule

    var body: some View {
        CallGlyph(module: module)
            .hudSlot(.leading)
    }
}

/// Right slot: who's calling, the call's running time (counted by SwiftUI itself), or "Ended".
struct CallCompactTrailing: View {
    let module: CallsModule

    var body: some View {
        Group {
            if let incoming = module.incoming {
                Text(incoming.caller)
                    .foregroundStyle(Theme.primary)
            } else if let call = module.call {
                Text(timerInterval: call.since...Date.distantFuture, countsDown: false)
                    .foregroundStyle(callGreen)
            } else if module.ended != nil {
                Text("Ended")
                    .foregroundStyle(callRed)
            }
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .hudSlot(.trailing)
    }
}

// MARK: - Expanded

/// The call, iPhone style: who or what, the time, and round Decline and Accept buttons while it
/// rings; mute and the call's app while it's on.
struct CallsExpandedView: View {
    let module: CallsModule

    var body: some View {
        Group {
            if let incoming = module.incoming {
                incomingRow(incoming)
            } else if let call = module.call {
                ongoing(call)
            } else if let ended = module.ended {
                row(bundleID: nil, title: "Call Ended", subtitle: ended.appName) {
                    Text(ClockFormat.duration(ended.duration))
                        .font(.system(size: 30, weight: .light).monospacedDigit())
                        .foregroundStyle(callRed)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func incomingRow(_ incoming: IncomingCall) -> some View {
        row(bundleID: incoming.appBundleID, title: incoming.caller, subtitle: incoming.detail ?? CallApps.name(for: incoming.appBundleID)) {
            HStack(spacing: 14) {
                CallRoundButton(symbol: "phone.down.fill", color: callRed, label: "Decline", action: module.decline)
                CallRoundButton(symbol: "phone.fill", color: callGreen, label: "Accept", action: module.answer)
            }
        }
    }

    private func ongoing(_ call: OngoingCall) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            row(bundleID: call.appBundleID, title: call.appName, subtitle: subtitle(call)) {
                Text(timerInterval: call.since...Date.distantFuture, countsDown: false)
                    .font(.system(size: 30, weight: .light).monospacedDigit())
                    .foregroundStyle(callGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            HStack(spacing: 8) {
                if module.canMuteMicrophone {
                    Button(action: module.toggleMicrophoneMute) {
                        Label(module.isMicrophoneMuted ? "Unmute" : "Mute", systemImage: module.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(NotchButtonStyle())
                    .help("Mutes the microphone for every app")
                }
                if call.appBundleID != nil {
                    Button("Show \(call.appName)", action: module.showCallApp)
                        .buttonStyle(NotchButtonStyle())
                }
            }
        }
    }

    private func subtitle(_ call: OngoingCall) -> String {
        var parts = [call.isVideo ? "Video call" : "On a call"]
        if module.isMicrophoneMuted { parts.append("Microphone muted") }
        return parts.joined(separator: " · ")
    }

    private func row(bundleID: String?, title: String, subtitle: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            AppIconView(bundleID: bundleID, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.title).lineLimit(1)
                Text(subtitle).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// An app's icon, or a phone in a rounded square when Notchi can't tell the app.
struct AppIconView: View {
    let bundleID: String?
    let size: CGFloat

    var body: some View {
        if let icon = CallApps.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "phone.fill")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(callGreen)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Theme.controlFill))
        }
    }
}

/// The iPhone's round call button.
struct CallRoundButton: View {
    let symbol: String
    let color: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(color))
        }
        .buttonStyle(CallRoundButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct CallRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.12 : 0)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Settings

/// Settings › Calls.
struct CallsSettingsView: View {
    let module: CallsModule

    @AppStorage(Preferences.Key.callsShowIncoming) private var showIncoming = true
    @AppStorage(Preferences.Key.callsIncludeBrowsers) private var includeBrowsers = Preferences.Default.callsIncludeBrowsers
    @AppStorage(Preferences.Key.callsAnnounceEnd) private var announceEnd = true
    @Environment(\.moduleRegistry) private var registry

    private var isEnabled: Bool { registry?.modules.contains { $0.id == module.id } ?? true }

    var body: some View {
        if registry != nil {
            Section {
                ModuleEnabledToggle(moduleID: module.id, title: "Show calls in the notch")
            }
        }

        Section {
            Toggle("Count calls in browsers (Meet, Teams on the web)", isOn: $includeBrowsers)
            Toggle("Show “Ended” when a call ends", isOn: $announceEnd)
            LabeledContent("Right now", value: status)
        } header: {
            Text("Calls")
        } footer: {
            SettingsFootnote("A call shows while FaceTime, Phone, Zoom, Teams, Slack, Discord or another calling app uses the microphone, with its running time. Hover over it for the app and a microphone mute that works for every app. Notchi sees which apps use the microphone without any permission.")
        }
        .disabled(!isEnabled)

        Section {
            Toggle("Show incoming calls", isOn: $showIncoming)
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
            Text("Incoming Calls")
        } footer: {
            SettingsFootnote("A FaceTime or iPhone call ringing on this Mac takes the middle of the notch with the caller's name; open the notch to answer or decline. Notchi reads the call from its Notification Center alert, which needs Accessibility.")
        }
        .disabled(!isEnabled)
    }

    private var status: String {
        if let incoming = module.incoming { return "\(incoming.caller) is calling" }
        if let call = module.call { return "On a call in \(call.appName)" }
        return "No call"
    }
}

// MARK: - Previews

#Preview("Expanded · incoming") {
    let module = CallsModule()
    module.applyIncoming(IncomingCall(caller: "Jane Appleseed", detail: "FaceTime Audio", appBundleID: CallApps.faceTime))
    return CallsExpandedView(module: module)
        .frame(width: 408, height: 126)
        .padding()
        .background(Theme.surface)
        .foregroundStyle(Theme.primary)
}
