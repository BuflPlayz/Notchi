import AppKit
import ImageIO

/// One animation: its frames and how long each shows.
struct SpriteStrip: @unchecked Sendable {
    let frames: [CGImage]
    let durations: [Duration]
    /// Frame size, in sprite pixels.
    let size: CGSize
    /// The mascot's body at rest, in sprite pixels: what a view fits to its size, so every mascot
    /// fills the same box however much empty canvas its frames have.
    let body: CGSize
    /// The point that stays put between animations (the bottom center of the body), in sprite
    /// pixels from the top left. Animations have different canvases; this keeps the body still.
    let anchor: CGPoint
    /// How far the animation draws above the body's top at most (a thought bubble, a jump), in
    /// sprite pixels.
    let reach: CGFloat
    /// Pixel art: scale without smoothing.
    let isPixelArt: Bool

    init(frames: [CGImage], durations: [Duration], size: CGSize, body: CGSize, anchor: CGPoint, isPixelArt: Bool) {
        self.frames = frames
        self.durations = durations
        self.size = size
        self.body = body
        self.anchor = anchor
        self.isPixelArt = isPixelArt
        let bodyTop = anchor.y - body.height
        reach = max(0, frames.compactMap { Self.opaqueBounds(of: $0).map { bodyTop - $0.minY } }.max() ?? 0)
    }

    /// The box around a frame's visible pixels, in pixels from the top left.
    static func opaqueBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Rows are stored top first. Faint edge pixels (soft shadows) don't count.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha[y * width + x] > 40 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

/// What a mascot is up to, from the session it stands for.
enum MascotPose: Hashable, Sendable {
    case idle
    case thinking
    /// Working on code: editing, writing, running commands.
    case working
    /// Reading and searching.
    case looking
    /// Handing work to a subagent.
    case delegating
    case waiting
    case celebrating
    case failed
}

// MARK: - Clawd

/// Clawd, Claude Code's mascot, from the copy of Claude's Clawd Quest game inside Claude.app.
///
/// The game keeps each animation as a palette plus per-frame pixel changes in a table in its
/// JavaScript (`clawdQuestEngine-*.js` in `app.asar`). This decodes the few Notchi uses, in memory,
/// so nothing of Claude's is copied into Notchi.
enum ClawdSprites {
    /// Clawd's animations for a pose, best first. Some reach well above him (a thought bubble, a
    /// jump); the later ones stay close to his body, for places without room above, like the notch.
    static func animationNames(for pose: MascotPose) -> [String] {
        switch pose {
        case .idle: []
        case .thinking: ["Thinking", "LookingAroundEyesOnly"]
        case .working: ["Laptop", "Desktop"]
        case .looking: ["LookingAround"]
        case .delegating: ["Running"]
        case .waiting: ["Waving", "Pointing", "LookingAround"]
        case .celebrating: ["JumpingHappy", "DancingHappy"]
        case .failed: ["Disappointed", "Facepalm"]
        }
    }

    /// Standing still: the first frame of his wave.
    static let restName = "Waving"

    static func load(fromApp appURL: URL) -> [String: SpriteStrip] {
        guard let archive = AsarArchive(url: appURL.appending(path: "Contents/Resources/app.asar")) else { return [:] }
        // Look where the engine usually lives first, then anywhere.
        let likely = archive.paths { $0.contains("clawdQuest") && $0.hasSuffix(".js") }
        let rest = archive.paths { $0.hasSuffix(".js") && !$0.contains("clawdQuest") && !$0.contains("node_modules") }
        for path in likely + rest {
            guard let data = archive.data(at: path), data.range(of: Data("clawd-quest: no sprite data".utf8)) != nil,
                  let source = String(data: data, encoding: .utf8), let table = spriteTable(in: source) else { continue }
            var strips: [String: SpriteStrip] = [:]
            let wanted = Set(MascotPoseNames.clawd + [restName])
            for (name, value) in table where wanted.contains(name) {
                if let sprite = value as? JSONObject, let strip = strip(from: sprite) { strips[name] = strip }
            }
            return strips
        }
        return [:]
    }

    /// The sprite table literal, `xx={BreakDancing:{cat:"Core",w:34,…},…}`, as JSON.
    static func spriteTable(in source: String) -> JSONObject? {
        guard let match = source.firstMatch(of: /\w+=\{\w+:\{cat:"/) else { return nil }
        let utf8 = Array(source.utf8[match.range.lowerBound...])
        guard let open = utf8.firstIndex(of: UInt8(ascii: "{")) else { return nil }
        var depth = 0
        var end: Int?
        for index in open..<utf8.count {
            if utf8[index] == UInt8(ascii: "{") { depth += 1 }
            if utf8[index] == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 { end = index; break }
            }
        }
        guard let end, var literal = String(bytes: utf8[open...end], encoding: .utf8) else { return nil }
        // The minifier writes some lists as "a(b(c".split("("); keys are bare identifiers.
        literal = literal.replacing(/"([^"]*)"\.split\("(.)"\)/) { match in
            let pieces = String(match.1).components(separatedBy: String(match.2))
            return (try? String(data: JSONSerialization.data(withJSONObject: pieces), encoding: .utf8)) ?? "[]"
        }
        literal = literal.replacing(/([{,])([A-Za-z_]\w*):/) { "\($0.1)\"\($0.2)\":" }
        return JSONObject.decode(Data(literal.utf8))
    }

    /// Decodes one sprite: a base frame of base-36 palette indices ("." is clear), then deltas
    /// listing the pixels that change from the frame before as `<base-36 position><new value>`.
    static func strip(from sprite: JSONObject) -> SpriteStrip? {
        guard let width = (sprite["w"] as? NSNumber)?.intValue, let height = (sprite["h"] as? NSNumber)?.intValue,
              let base = sprite.string("base"), base.count == width * height,
              let palette = (sprite["palette"] as? [String])?.map(rgba) else { return nil }
        let fps = max((sprite["fps"] as? NSNumber)?.intValue ?? 8, 1)
        var pixels = base.map(value)
        var frames: [[Int?]] = [pixels]
        for delta in sprite["deltas"] as? [Any] ?? [] {
            for change in (delta as? String ?? "").split(separator: ",") where change.count >= 2 {
                if let position = Int(change.dropLast(), radix: 36), pixels.indices.contains(position) {
                    pixels[position] = value(change.last!)
                }
            }
            frames.append(pixels)
        }
        let images = frames.compactMap { image(width: width, height: height, pixels: $0, palette: palette) }
        let body = (sprite["a0"] as? [NSNumber])?.map { CGFloat($0.doubleValue) } ?? [0, 0, CGFloat(width), CGFloat(height)]
        guard !images.isEmpty, body.count == 4 else { return nil }
        return SpriteStrip(
            frames: images,
            durations: Array(repeating: .milliseconds(1000 / fps), count: images.count),
            size: CGSize(width: width, height: height),
            body: CGSize(width: body[2], height: body[3]),
            anchor: CGPoint(x: body[0] + body[2] / 2, y: body[1] + body[3]),
            isPixelArt: true
        )
    }

    private static func value(_ character: Character) -> Int? {
        character == "." ? nil : Int(String(character), radix: 36)
    }

    private static func rgba(_ hex: String) -> [UInt8] {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let number = UInt32(digits, radix: 16) ?? 0
        return [UInt8(number >> 16 & 0xFF), UInt8(number >> 8 & 0xFF), UInt8(number & 0xFF), 0xFF]
    }

    private static func image(width: Int, height: Int, pixels: [Int?], palette: [[UInt8]]) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (index, pixel) in pixels.enumerated() {
            guard let pixel, palette.indices.contains(pixel) else { continue }
            bytes.replaceSubrange(index * 4..<index * 4 + 4, with: palette[pixel])
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

/// The animations each mascot needs, so loaders decode only those.
enum MascotPoseNames {
    static let poses: [MascotPose] = [.idle, .thinking, .working, .looking, .delegating, .waiting, .celebrating, .failed]
    static var clawd: [String] { poses.flatMap(ClawdSprites.animationNames) }
}

// MARK: - Codex pets

/// The pet Codex shows, from the Codex app's settings: one of its built-in pets (packed in the app),
/// or one the user hatched in `~/.codex/pets/<id>/`.
///
/// Pets are 8 × 11 atlases of 192 × 208 cells. Rows 0–8 are the standard animations, each with its
/// own frame count and timing (below, as Codex plays them); rows 9–10 are look directions.
enum CodexPetSprites {
    static let columns = 8
    static let rows = 11

    /// Each standard row's frame durations in milliseconds: idle, running right, running left,
    /// waving, jumping, failed, waiting, running (at work), review.
    private static let rowTimings: [Int: [Int]] = [
        0: [280, 110, 110, 140, 140, 320].map { $0 * 3 },
        1: timing(frames: 8, each: 120, last: 220),
        3: timing(frames: 4, each: 140, last: 280),
        4: timing(frames: 5, each: 140, last: 280),
        5: timing(frames: 8, each: 140, last: 240),
        6: timing(frames: 6, each: 150, last: 260),
        7: timing(frames: 6, each: 120, last: 220),
        8: timing(frames: 6, each: 150, last: 280),
    ]

    /// The rows for a pose, best first; a jump that doesn't fit falls back to a wave.
    static func rows(for pose: MascotPose) -> [Int] {
        switch pose {
        case .idle: [0]
        case .thinking, .looking: [8]
        case .working: [7]
        case .delegating: [1]
        case .waiting: [6]
        case .celebrating: [4, 3]
        case .failed: [5]
        }
    }

    private static func timing(frames: Int, each: Int, last: Int) -> [Int] {
        (0..<frames).map { $0 == frames - 1 ? last : each }
    }

    struct Pet: @unchecked Sendable {
        let name: String
        /// By atlas row.
        let strips: [Int: SpriteStrip]
    }

    /// The selected pet's atlas, or nil if there's none to be found.
    static func load(home: URL, appURL: URL?) -> Pet? {
        let selected = selectedPetID(home: home)
        // A pet the user hatched.
        if let selected, let pet = customPet(id: selected, home: home) { return pet }
        // A built-in pet, packed in the Codex app.
        if let appURL, let archive = AsarArchive(url: appURL.appending(path: "Contents/Resources/app.asar")) {
            for id in [selected, "codex"].compactMap({ $0 }) {
                let pattern = "/\(id)-spritesheet-v"
                if let path = archive.paths(where: { $0.contains(pattern) && $0.hasSuffix(".webp") }).last,
                   let data = archive.data(at: path), let atlas = image(from: data) {
                    return Pet(name: id.capitalized, strips: strips(from: atlas))
                }
            }
        }
        // Any hatched pet, as a last resort.
        let pets = (try? FileManager.default.contentsOfDirectory(at: home.appending(path: ".codex/pets"), includingPropertiesForKeys: nil)) ?? []
        return pets.lazy.compactMap { customPet(id: $0.lastPathComponent, home: home) }.first
    }

    /// `selected-avatar-id = "codex"` in `~/.codex/config.toml`.
    static func selectedPetID(home: URL) -> String? {
        guard let config = try? String(contentsOf: home.appending(path: ".codex/config.toml"), encoding: .utf8),
              let match = config.firstMatch(of: /selected-avatar-id\s*=\s*"([^"]+)"/) else { return nil }
        let id = String(match.1)
        return id.hasPrefix("uploaded:") ? String(id.dropFirst("uploaded:".count)) : id
    }

    private static func customPet(id: String, home: URL) -> Pet? {
        let folder = home.appending(path: ".codex/pets/\(id)", directoryHint: .isDirectory)
        guard let manifest = (try? Data(contentsOf: folder.appending(path: "pet.json"))).flatMap(JSONObject.decode) else { return nil }
        let sheet = folder.appending(path: manifest.string("spritesheetPath") ?? "spritesheet.webp")
        guard let data = try? Data(contentsOf: sheet), let atlas = image(from: data) else { return nil }
        return Pet(name: manifest.string("displayName") ?? id.capitalized, strips: strips(from: atlas))
    }

    private static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func strips(from atlas: CGImage) -> [Int: SpriteStrip] {
        let cell = CGSize(width: atlas.width / columns, height: atlas.height / rows)
        func frame(row: Int, column: Int) -> CGImage? {
            atlas.cropping(to: CGRect(x: CGFloat(column) * cell.width, y: CGFloat(row) * cell.height, width: cell.width, height: cell.height))
        }
        // The pet fills only part of its cell, and every row is drawn to the same spot in it, so the
        // first idle frame's outline is the body for all of them.
        let body = frame(row: 0, column: 0).flatMap(SpriteStrip.opaqueBounds) ?? CGRect(origin: .zero, size: cell)
        var strips: [Int: SpriteStrip] = [:]
        for (row, durations) in rowTimings {
            let frames = durations.indices.compactMap { frame(row: row, column: $0) }
            guard !frames.isEmpty else { continue }
            strips[row] = SpriteStrip(
                frames: frames,
                durations: durations.prefix(frames.count).map { .milliseconds($0) },
                size: cell,
                body: body.size,
                anchor: CGPoint(x: body.midX, y: body.maxY),
                isPixelArt: false
            )
        }
        return strips
    }
}
