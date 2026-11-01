import CoreGraphics
import Foundation
import Testing
@testable import Notchi

struct AdapterStreamParserTests {
    private let full = """
    {"type":"data","diff":false,"payload":{"title":"Song","artist":"Band","album":"","durationMicros":200000000,\
    "elapsedTimeMicros":30000000,"timestampEpochMicros":1700000000000000,"playbackRate":1,"playing":true,\
    "bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari",\
    "artworkData":"AQID"}}
    """

    @Test func parsesFullPayload() throws {
        var parser = AdapterStreamParser()
        guard case .update(let info?) = parser.consume(full) else {
            Issue.record("expected an update")
            return
        }
        #expect(info.title == "Song")
        #expect(info.artist == "Band")
        #expect(info.album == nil)                                  // empty strings become nil
        #expect(info.duration == 200)
        #expect(info.elapsed == 30)
        #expect(info.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(info.isPlaying)
        #expect(info.sourceBundleIdentifier == "com.apple.Safari")  // browser, not its helper
        #expect(info.artworkData == Data([1, 2, 3]))
    }

    @Test func diffMergesAndNullRemoves() {
        var parser = AdapterStreamParser()
        _ = parser.consume(full)
        let diff = #"{"type":"data","diff":true,"payload":{"playing":false,"artist":null}}"#
        guard case .update(let info?) = parser.consume(diff) else {
            Issue.record("expected an update")
            return
        }
        #expect(info.title == "Song")
        #expect(!info.isPlaying)
        #expect(info.artist == nil)
        #expect(info.artworkData == Data([1, 2, 3]))                // kept from the earlier full payload
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        var parser = AdapterStreamParser()
        _ = parser.consume(full)
        #expect(parser.consume(#"{"type":"data","diff":false,"payload":{}}"#) == .update(nil))
    }

    @Test func ignoresNoise() {
        var parser = AdapterStreamParser()
        #expect(parser.consume("not json") == .ignored)
        #expect(parser.consume(#"{"type":"other","payload":{}}"#) == .ignored)
    }
}

struct NowPlayingInfoTests {
    private func info(playing: Bool, rate: Double = 1) -> NowPlayingInfo {
        var info = NowPlayingInfo.sample
        info.elapsed = 10
        info.duration = 100
        info.timestamp = Date(timeIntervalSince1970: 0)
        info.isPlaying = playing
        info.playbackRate = rate
        return info
    }

    @Test func extrapolatesWhilePlaying() {
        #expect(info(playing: true).elapsed(at: Date(timeIntervalSince1970: 5)) == 15)
        #expect(info(playing: true, rate: 2).elapsed(at: Date(timeIntervalSince1970: 5)) == 20)
        #expect(info(playing: true, rate: 0).elapsed(at: Date(timeIntervalSince1970: 5)) == 15)
    }

    @Test func holdsWhilePausedAndClampsToDuration() {
        #expect(info(playing: false).elapsed(at: Date(timeIntervalSince1970: 50)) == 10)
        #expect(info(playing: true).elapsed(at: Date(timeIntervalSince1970: 500)) == 100)
    }

    @Test func formatsTimes() {
        #expect(PlaybackProgressView.format(63) == "1:03")
        #expect(PlaybackProgressView.format(3725) == "1:02:05")
        #expect(PlaybackProgressView.format(-4) == "0:00")
    }
}

struct ArtworkPaletteTests {
    /// An image filled with `base`, with an optional `patch` color covering `patchFraction` of it.
    private func image(base: RGB, patch: RGB? = nil, patchFraction: Double = 0) -> CGImage {
        let size = 48
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: base.red, green: base.green, blue: base.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        if let patch {
            context.setFillColor(CGColor(srgbRed: patch.red, green: patch.green, blue: patch.blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: Double(size) * patchFraction, height: Double(size)))
        }
        return context.makeImage()!
    }

    @Test func picksDominantHue() throws {
        let accent = try #require(ArtworkPalette.accent(from: image(base: RGB(red: 0.8, green: 0.1, blue: 0.1))))
        #expect(accent.red > 0.7 && accent.green < 0.3 && accent.blue < 0.3)
    }

    @Test func findsColorOnDarkArtwork() throws {
        let artwork = image(base: RGB(red: 0.02, green: 0.02, blue: 0.02), patch: RGB(red: 0.1, green: 0.3, blue: 0.9), patchFraction: 0.3)
        let accent = try #require(ArtworkPalette.accent(from: artwork))
        #expect(accent.blue > accent.red && accent.blue > accent.green)
        #expect(HSB(accent).brightness >= 0.8)                       // lifted to read on black
    }

    @Test func grayscaleHasNoAccent() {
        #expect(ArtworkPalette.accent(from: image(base: RGB(red: 0.5, green: 0.5, blue: 0.5))) == nil)
        #expect(ArtworkPalette.accent(from: image(base: RGB(red: 0, green: 0, blue: 0))) == nil)
    }

    @Test func hsbRoundTrips() {
        for color in [RGB(red: 1, green: 0.5, blue: 0), RGB(red: 0.2, green: 0.4, blue: 0.9), RGB(red: 0.7, green: 0.1, blue: 0.6)] {
            let back = HSB(color).rgb
            #expect(abs(back.red - color.red) < 0.001 && abs(back.green - color.green) < 0.001 && abs(back.blue - color.blue) < 0.001)
        }
    }

    @Test func decodesSampleArtwork() throws {
        let data = try #require(SampleArtwork.pngData())
        let decoded = try #require(ArtworkPalette.decode(data, maxPixelSize: 64))
        #expect(decoded.image.width <= 64)
        #expect(decoded.accent != nil)
    }

    @Test func glowLeavesRoomForTheBlur() throws {
        let glow = try #require(ArtworkPalette.glow(from: image(base: RGB(red: 0.8, green: 0.1, blue: 0.1)), side: 84, blurRadius: 16))
        #expect(glow.width == 84 + 2 * 48 && glow.height == glow.width)
        let corner = try #require(glow.dataProvider?.data as Data?)
        #expect(corner[3] == 0)                                      // the fade is gone by the edge
    }
}

@MainActor
struct MediaModuleTests {
    @Test func playingShowsLiveActivityAndPauseLingers() async throws {
        let provider = MockNowPlayingProvider()
        let module = MediaModule(provider: provider, pauseLinger: .milliseconds(50))
        module.start()
        #expect(module.liveActivity?.priority == .active)

        module.perform(.togglePlayPause)
        #expect(module.info?.isPlaying == false)                     // optimistic update
        #expect(module.liveActivity != nil)                          // still lingering
        try await Task.sleep(for: .milliseconds(150))
        #expect(module.liveActivity == nil)
        #expect(provider.sentCommands == [.togglePlayPause])
    }

    @Test func resumingDuringLingerKeepsActivity() async throws {
        let provider = MockNowPlayingProvider()
        let module = MediaModule(provider: provider, pauseLinger: .milliseconds(80))
        module.start()
        module.perform(.pause)
        module.perform(.play)
        try await Task.sleep(for: .milliseconds(150))
        #expect(module.liveActivity != nil)
    }

    @Test func nothingPlayingHasNoActivity() {
        let module = MediaModule(provider: MockNowPlayingProvider(info: nil))
        module.start()
        #expect(module.info == nil)
        #expect(module.liveActivity == nil)
    }

    @Test func seekUpdatesPositionImmediately() {
        let module = MediaModule(provider: MockNowPlayingProvider())
        module.start()
        module.perform(.seek(to: 120))
        #expect(abs((module.info?.elapsed ?? 0) - 120) < 0.5)
    }
}
