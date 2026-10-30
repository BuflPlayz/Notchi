import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// In-memory provider for previews and tests. Commands change its state like a real player would.
@MainActor
final class MockNowPlayingProvider: NowPlayingProvider {
    var onUpdate: ((NowPlayingInfo?) -> Void)?
    let sourceName = "Preview"
    private(set) var info: NowPlayingInfo?
    private(set) var sentCommands: [MediaCommand] = []

    init(info: NowPlayingInfo? = .sample) {
        self.info = info
    }

    func start() { onUpdate?(info) }
    func stop() {}

    func send(_ command: MediaCommand) {
        sentCommands.append(command)
        guard var info else { return }
        info.elapsed = info.elapsed(at: Date())
        info.timestamp = Date()
        switch command {
        case .play: info.isPlaying = true
        case .pause: info.isPlaying = false
        case .togglePlayPause: info.isPlaying.toggle()
        case .nextTrack, .previousTrack: info.elapsed = 0
        case .seek(let position): info.elapsed = position
        }
        update(info)
    }

    /// Simulates the player changing on its own (track change, pause from the keyboard…).
    func update(_ newInfo: NowPlayingInfo?) {
        info = newInfo
        onUpdate?(newInfo)
    }
}

extension NowPlayingInfo {
    /// A playing track with generated artwork.
    static let sample = NowPlayingInfo(
        title: "Midnight Drive",
        artist: "Neon Coast",
        album: "Afterglow",
        duration: 214,
        elapsed: 63,
        timestamp: Date(),
        playbackRate: 1,
        isPlaying: true,
        artworkData: SampleArtwork.pngData(),
        sourceBundleIdentifier: "com.apple.Music"
    )
}

/// Draws a gradient "album cover" so previews don't need bundled images.
enum SampleArtwork {
    static func pngData(size: Int = 300) -> Data? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let colors = [
            CGColor(srgbRed: 0.98, green: 0.36, blue: 0.47, alpha: 1),
            CGColor(srgbRed: 0.45, green: 0.18, blue: 0.75, alpha: 1),
            CGColor(srgbRed: 0.08, green: 0.05, blue: 0.2, alpha: 1),
        ] as CFArray
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.55, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])
        context.setFillColor(CGColor(srgbRed: 1, green: 0.85, blue: 0.6, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: size / 4, y: size / 3, width: size / 2, height: size / 2))

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
