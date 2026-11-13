import SwiftUI

/// Version, updates, acknowledgements, and a way to quit (Notchi has no Dock icon or menu bar item).
struct AboutSettingsView: View {
    @AppStorage(Preferences.Key.checkForUpdates) private var checkForUpdates = true
    @State private var updates = UpdateChecker.shared

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    // In a scroll view like every other pane: a pane without one blanks the Settings sidebar's rows.
    var body: some View {
        ScrollView {
            content
                // Capped, or the acknowledgement asks for one long line.
                .frame(maxWidth: 380)
                .padding(28)
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
    }

    private var content: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            VStack(spacing: 4) {
                Text("Notchi").font(.title2.weight(.semibold))
                Text(version).foregroundStyle(.secondary)
                Text("A Dynamic Island for your Mac's notch.")
                    .foregroundStyle(.secondary)
                Text("© 2026 BuflPlayz · MIT License")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            updatesSection

            Divider().padding(.horizontal, 40)

            VStack(spacing: 4) {
                Text("Acknowledgements").font(.headline)
                Text("Now playing uses **mediaremote-adapter** by Jonas van den Berg and contributors, under the BSD 3-Clause License.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("github.com/ungive/mediaremote-adapter", destination: URL(string: "https://github.com/ungive/mediaremote-adapter")!)
            }
            .font(.callout)

            Button("Quit Notchi") { NSApp.terminate(nil) }
                .padding(.top, 4)
        }
    }
}

extension AboutSettingsView {
    private var updatesSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button("Check for Updates…") {
                    Task { await updates.check(userInitiated: true) }
                }
                .disabled(isBusy)
                if case .available(let release) = updates.status {
                    if updates.canInstall(release) {
                        Button("Install \(release.version)") { updates.install(release) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Download \(release.version)") { updates.download(release) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            Toggle("Check for updates automatically", isOn: $checkForUpdates)
                .toggleStyle(.checkbox)
            Text(updateStatus)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var isBusy: Bool {
        switch updates.status {
        case .checking, .installing: true
        default: false
        }
    }

    private var updateStatus: String {
        switch updates.status {
        case .checking: return "Checking…"
        case .installing(let release): return "Installing Notchi \(release.version)…"
        case .available(let release): return "Notchi \(release.version) is available."
        case .failed: return "Couldn't reach GitHub."
        case .idle, .upToDate:
            guard let lastChecked = updates.lastChecked else { return "Not checked yet." }
            return "Last checked \(lastChecked.formatted(.relative(presentation: .named)))."
        }
    }
}

#Preview("About") {
    AboutSettingsView()
        .frame(width: 500)
}
