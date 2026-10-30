import CoreGraphics
import Foundation
import ImageIO

/// An sRGB color with components in 0…1.
struct RGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

/// Derives the media accent color from album artwork.
enum ArtworkPalette {
    /// Decodes artwork at a small size (it's only ever shown at ≤ 84 pt) and extracts its accent.
    /// Pure and thread-safe; call it off the main actor.
    static func decode(_ data: Data, maxPixelSize: Int = 256) -> (image: CGImage, accent: RGB?)? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        return (image, accent(from: image))
    }

    /// The most common vivid hue family in the image, lifted so it reads on black.
    /// Returns nil for grayscale or near-black artwork; callers fall back to white.
    static func accent(from image: CGImage) -> RGB? {
        let side = 24
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        // Bucket colorful pixels by hue, weighted by how vivid they are.
        let binCount = 18
        var weights = [Double](repeating: 0, count: binCount)
        var sums = [RGB](repeating: RGB(red: 0, green: 0, blue: 0), count: binCount)
        for index in 0..<(side * side) {
            let offset = index * 4
            let color = RGB(red: Double(pixels[offset]) / 255, green: Double(pixels[offset + 1]) / 255, blue: Double(pixels[offset + 2]) / 255)
            let hsb = HSB(color)
            guard hsb.saturation > 0.25, hsb.brightness > 0.2 else { continue }
            let bin = min(Int(hsb.hue * Double(binCount)), binCount - 1)
            let weight = hsb.saturation * hsb.brightness
            weights[bin] += weight
            sums[bin].red += color.red * weight
            sums[bin].green += color.green * weight
            sums[bin].blue += color.blue * weight
        }

        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }),
              weights[best] > Double(side * side) * 0.02
        else { return nil }

        let average = RGB(red: sums[best].red / weights[best], green: sums[best].green / weights[best], blue: sums[best].blue / weights[best])
        var hsb = HSB(average)
        hsb.saturation = min(hsb.saturation, 0.85)
        hsb.brightness = max(hsb.brightness, 0.8)
        return hsb.rgb
    }
}

/// Hue, saturation and brightness in 0…1.
struct HSB: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(_ color: RGB) {
        let maxValue = max(color.red, color.green, color.blue)
        let minValue = min(color.red, color.green, color.blue)
        let delta = maxValue - minValue
        brightness = maxValue
        saturation = maxValue == 0 ? 0 : delta / maxValue
        guard delta > 0 else { hue = 0; return }
        var degrees: Double
        if maxValue == color.red {
            degrees = 60 * ((color.green - color.blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxValue == color.green {
            degrees = 60 * ((color.blue - color.red) / delta + 2)
        } else {
            degrees = 60 * ((color.red - color.green) / delta + 4)
        }
        if degrees < 0 { degrees += 360 }
        hue = degrees / 360
    }

    var rgb: RGB {
        let chroma = brightness * saturation
        let sector = hue * 6
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - chroma
        let (r, g, b): (Double, Double, Double) = switch Int(sector) % 6 {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        return RGB(red: r + m, green: g + m, blue: b + m)
    }
}
