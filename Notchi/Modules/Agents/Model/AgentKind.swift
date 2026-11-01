import SwiftUI

/// The coding agents Notchi follows.
enum AgentKind: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case gemini

    var id: Self { self }

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        }
    }

    /// The agent's color, for progress and fallbacks: Claude's clay, Codex's blue, Gemini's blue.
    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.42, green: 0.53, blue: 1)
        case .gemini: Color(red: 0.31, green: 0.55, blue: 0.97)
        }
    }

    /// The desktop app that carries the agent's mascot, if it has one.
    var appBundleID: String? {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        case .gemini: nil
        }
    }

    /// The agent's own folder in the home directory; it exists once the agent has run.
    var homeFolder: String {
        switch self {
        case .claude: ".claude"
        case .codex: ".codex"
        case .gemini: ".gemini"
        }
    }
}
