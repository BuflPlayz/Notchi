import AppKit
import SwiftUI

/// Each agent's mascot, taken from the agent's own app the first time it's needed: Clawd from
/// Claude.app, the selected pet from the Codex app (or `~/.codex/pets`). Agents without one, or
/// whose app isn't installed, show their app's icon or a tinted symbol.
@MainActor
@Observable
final class AgentMascots {
    static let shared = AgentMascots()

    enum Source: Equatable {
        case loading
        /// Animated sprites; `name` is the mascot's ("Clawd", "Codex", a hatched pet's name).
        case sprites(name: String, app: String)
        case appIcon(app: String)
        case symbol
    }

    private(set) var clawd: [String: SpriteStrip] = [:]
    private(set) var codexPet: CodexPetSprites.Pet?
    private(set) var sources: [AgentKind: Source] = [:]
    private var appIcons: [AgentKind: NSImage] = [:]
    @ObservationIgnored private var requested: Set<AgentKind> = []
    @ObservationIgnored private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func source(for kind: AgentKind) -> Source {
        sources[kind] ?? .loading
    }

    /// The animation for `pose`, for a body `height` points tall that may reach `headroom` points
    /// above it. A tall animation (Clawd's thought bubble, a jump) gives way to one that fits.
    func strip(for kind: AgentKind, pose: MascotPose, height: CGFloat, headroom: CGFloat = .infinity) -> SpriteStrip? {
        let candidates: [SpriteStrip]
        switch kind {
        case .claude:
            candidates = ClawdSprites.animationNames(for: pose).compactMap { clawd[$0] }
            if candidates.isEmpty, let rest = clawd[ClawdSprites.restName] {
                // Standing still: the first frame of the wave.
                return SpriteStrip(frames: Array(rest.frames.prefix(1)), durations: [.seconds(1)], size: rest.size,
                                   body: rest.body, anchor: rest.anchor, isPixelArt: true)
            }
        case .codex:
            candidates = CodexPetSprites.rows(for: pose).compactMap { codexPet?.strips[$0] }
            if candidates.isEmpty { return codexPet?.strips[0] }
        case .gemini:
            return nil
        }
        let reach = { (strip: SpriteStrip) in strip.reach * height / strip.body.height }
        return candidates.first { reach($0) <= headroom } ?? candidates.min { reach($0) < reach($1) }
    }

    func appIcon(for kind: AgentKind) -> NSImage? {
        appIcons[kind]
    }

    /// Starts loading a mascot, once; views update when it arrives. Called when an agent first shows
    /// up, never from a view's body.
    func load(_ kind: AgentKind) {
        guard !requested.contains(kind) else { return }
        requested.insert(kind)
        let appURL = kind.appBundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        if let appURL {
            appIcons[kind] = NSWorkspace.shared.icon(forFile: appURL.path)
        }
        let appName = appURL?.deletingPathExtension().lastPathComponent ?? kind.name
        let fallback: Source = appURL == nil ? .symbol : .appIcon(app: appName)
        let home = home
        switch kind {
        case .claude:
            guard let appURL else { sources[kind] = fallback; return }
            Task.detached(priority: .utility) {
                let strips = ClawdSprites.load(fromApp: appURL)
                await MainActor.run {
                    self.clawd = strips
                    self.sources[kind] = strips.isEmpty ? fallback : .sprites(name: "Clawd", app: appName)
                }
            }
        case .codex:
            Task.detached(priority: .utility) {
                let pet = CodexPetSprites.load(home: home, appURL: appURL)
                await MainActor.run {
                    self.codexPet = pet
                    self.sources[kind] = pet.map { .sprites(name: $0.name, app: appURL == nil ? "~/.codex/pets" : appName) } ?? fallback
                }
            }
        case .gemini:
            sources[kind] = fallback
        }
    }
}

extension AgentSession {
    /// What the mascot acts out.
    var pose: MascotPose {
        switch phase {
        case .idle: return .idle
        case .thinking: return .thinking
        case .needsInput: return .waiting
        case .finished: return outcome == .failure ? .failed : .celebrating
        case .working:
            switch step?.symbol {
            case "magnifyingglass", "doc.text", "globe": return .looking
            case "person.2": return .delegating
            default: return .working
            }
        }
    }
}

/// An agent's mascot acting out a pose, `height` points tall (the body). Animations may reach up to
/// `headroom` points above it (a thought bubble, a jump); taller ones are swapped for ones that fit.
struct AgentMascotView: View {
    let kind: AgentKind
    let pose: MascotPose
    var height: CGFloat = 22
    var headroom: CGFloat = .infinity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var mascots: AgentMascots { .shared }

    var body: some View {
        Group {
            if let strip = mascots.strip(for: kind, pose: pose, height: height, headroom: headroom) {
                SpriteView(strip: strip, animates: !reduceMotion, height: height)
            } else if let icon = mascots.appIcon(for: kind), let image = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                LayerAnimationView(frames: [image], pulses: isBusy, animates: !reduceMotion)
                    .frame(width: height, height: height)
            } else {
                // Fills the same box as a sprite's body.
                LayerSymbol(
                    name: kind == .gemini ? "sparkle" : "terminal.fill",
                    style: kind == .gemini ? AnyShapeStyle(geminiGradient) : AnyShapeStyle(kind.tint),
                    styleKey: kind.rawValue,
                    size: height,
                    pulses: isBusy
                )
            }
        }
        .accessibilityLabel(kind.name)
    }

    private var isBusy: Bool {
        switch pose {
        case .idle, .celebrating, .failed: false
        default: true
        }
    }

    private var geminiGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.31, green: 0.55, blue: 0.97), Color(red: 0.66, green: 0.45, blue: 0.95)], startPoint: .bottomLeading, endPoint: .topTrailing)
    }

}

/// Plays a sprite strip in a box the size of the mascot's body, `height` points tall, with the body's
/// bottom center pinned to the box's. What the animation draws around the body spills outside.
/// The frames play in Core Animation (`LayerAnimationView`), not in SwiftUI.
private struct SpriteView: View {
    let strip: SpriteStrip
    let animates: Bool
    let height: CGFloat

    var body: some View {
        let scale = height / strip.body.height
        let box = CGSize(width: strip.body.width * scale, height: height)
        Color.clear
            .frame(width: box.width, height: box.height)
            .overlay(alignment: .topLeading) {
                LayerAnimationView(frames: strip.frames, durations: strip.durations, pixelArt: strip.isPixelArt, animates: animates)
                    .frame(width: strip.size.width * scale, height: strip.size.height * scale)
                    .offset(x: box.width / 2 - strip.anchor.x * scale, y: box.height - strip.anchor.y * scale)
                    .allowsHitTesting(false)
            }
    }
}
