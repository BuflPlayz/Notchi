import AppKit
import SwiftUI

/// Album artwork with continuous corners, or a placeholder note when there's none.
struct MediaArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.controlFill
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The playing app's icon, shown as a small badge on the artwork.
struct SourceAppBadge: View {
    let bundleIdentifier: String?
    var size: CGFloat = 22

    var body: some View {
        if let icon = Self.icon(for: bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
    }

    private static var cache: [String: NSImage] = [:]

    @MainActor
    private static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        if let cached = cache[bundleIdentifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleIdentifier] = icon
        return icon
    }
}

#Preview("Artwork") {
    HStack(spacing: 16) {
        MediaArtworkView(image: SampleArtwork.pngData().flatMap(NSImage.init(data:)), size: 84, cornerRadius: 16)
            .overlay(alignment: .bottomTrailing) {
                SourceAppBadge(bundleIdentifier: "com.apple.Music").offset(x: 5, y: 5)
            }
        MediaArtworkView(image: nil, size: 84, cornerRadius: 16)
        MediaArtworkView(image: nil, size: 22, cornerRadius: 6)
    }
    .padding(24)
    .background(Theme.surface)
}
