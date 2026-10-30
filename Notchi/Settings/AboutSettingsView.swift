import SwiftUI

/// Version, acknowledgements, and a way to quit (Notchi has no Dock icon or menu bar item).
struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black)
                    .frame(width: 72, height: 72)
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(Color(white: 0.18))
                    .frame(width: 34, height: 12)
                    .offset(y: -30)
            }
            VStack(spacing: 4) {
                Text("Notchi").font(.title2.weight(.semibold))
                Text(version).foregroundStyle(.secondary)
                Text("A Dynamic Island for your Mac's notch.")
                    .foregroundStyle(.secondary)
            }

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
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("About") {
    AboutSettingsView()
        .frame(width: 500)
}
