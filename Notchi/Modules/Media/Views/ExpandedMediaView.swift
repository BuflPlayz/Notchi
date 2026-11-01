import SwiftUI

/// The media page in the expanded panel.
struct ExpandedMediaView: View {
    let module: MediaModule

    var body: some View {
        if let info = module.info {
            NowPlayingView(module: module, info: info)
        } else {
            NothingPlayingView()
        }
    }
}

/// Artwork (with a soft glow of its own colors), title and artist, progress, and transport controls.
private struct NowPlayingView: View {
    let module: MediaModule
    let info: NowPlayingInfo

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            artwork
            VStack(alignment: .leading, spacing: 0) {
                Text(info.title)
                    .font(Theme.title)
                    .lineLimit(1)
                Text(info.artist ?? info.album ?? " ")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                PlaybackProgressView(info: info, accent: module.accent) { module.perform(.seek(to: $0)) }
                Spacer(minLength: 2)
                controls
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var artwork: some View {
        Button(action: module.openSourceApp) {
            MediaArtworkView(image: module.artwork, size: 84, cornerRadius: 16)
                .notchMatchedGeometry(id: "media.artwork")
                .background {
                    // The artwork's own colors, blurred, as a subtle glow on the black surface.
                    // Pre-blurred at its natural size, which already includes room for the fade.
                    if let glow = module.artworkGlow {
                        Image(nsImage: glow)
                            .opacity(0.45)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    SourceAppBadge(bundleIdentifier: info.sourceBundleIdentifier)
                        .offset(x: 5, y: 5)
                }
        }
        .buttonStyle(.plain)
        .help("Open the app that's playing")
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button { module.perform(.previousTrack) } label: {
                Image(systemName: "backward.fill").font(.system(size: 15))
            }
            .help("Previous")
            Button { module.perform(.togglePlayPause) } label: {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 21))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24)
            }
            .help(info.isPlaying ? "Pause" : "Play")
            Button { module.perform(.nextTrack) } label: {
                Image(systemName: "forward.fill").font(.system(size: 15))
            }
            .help("Next")
        }
        .buttonStyle(MediaControlButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

private struct NothingPlayingView: View {
    var body: some View {
        HStack(spacing: 16) {
            MediaArtworkView(image: nil, size: 84, cornerRadius: 16)
                .notchMatchedGeometry(id: "media.artwork")
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing playing")
                    .font(Theme.title)
                Text("Play something in Music, Spotify or your browser.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Bare glyph buttons that dim and shrink a little when pressed.
private struct MediaControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.primary)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview("Playing") {
    let module = MediaModule(provider: MockNowPlayingProvider())
    module.start()
    return ExpandedMediaView(module: module)
        .frame(width: 408, height: 126)
        .padding()
        .background(Theme.surface)
        .foregroundStyle(Theme.primary)
}

#Preview("Nothing playing") {
    let module = MediaModule(provider: MockNowPlayingProvider(info: nil))
    module.start()
    return ExpandedMediaView(module: module)
        .frame(width: 408, height: 126)
        .padding()
        .background(Theme.surface)
        .foregroundStyle(Theme.primary)
}
