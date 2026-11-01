import Foundation

/// Adds Notchi's hook to an agent's config, or takes it out again.
///
/// Hooks are optional: without them Notchi reads the agents' session files. With them, each agent
/// runs `notchi-agent-hook <agent>` on every step, which drops the event (the JSON the agent pipes
/// to hooks) in Notchi's inbox. The script returns at once and prints nothing, so it never slows an
/// agent down or changes what it does, and it drops events while Notchi isn't running.
///
/// The configs are the agents' own: `~/.claude/settings.json`, `~/.codex/hooks.json` and
/// `~/.gemini/settings.json`. Only entries that run Notchi's script are touched, and the original
/// file is kept as `<name>.notchi-backup` the first time Notchi changes it.
struct AgentHookInstaller: Sendable {
    let paths: AgentPaths

    init(paths: AgentPaths = .standard) {
        self.paths = paths
    }

    enum InstallError: LocalizedError {
        case unreadableConfig(URL)

        var errorDescription: String? {
            switch self {
            case .unreadableConfig(let url): "Notchi couldn't read \(url.path) as JSON, so it left the file alone."
            }
        }
    }

    /// The config file that holds the agent's hooks.
    func configURL(for kind: AgentKind) -> URL {
        switch kind {
        case .claude: paths.home.appending(path: ".claude/settings.json")
        case .codex: paths.home.appending(path: ".codex/hooks.json")
        case .gemini: paths.home.appending(path: ".gemini/settings.json")
        }
    }

    /// The agent's events Notchi listens to.
    static func events(for kind: AgentKind) -> [String] {
        switch kind {
        case .claude:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "PreCompact", "Stop", "SessionEnd"]
        case .codex:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "PreCompact", "Stop", "Interrupt", "SessionEnd"]
        case .gemini:
            ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "PreCompress", "AfterAgent", "SessionEnd"]
        }
    }

    /// The agent has been run on this Mac (its folder exists).
    func isAgentPresent(_ kind: AgentKind) -> Bool {
        FileManager.default.fileExists(atPath: paths.home.appending(path: kind.homeFolder).path)
    }

    func isInstalled(_ kind: AgentKind) -> Bool {
        guard let config = try? readConfig(kind), let hooks = config["hooks"] as? JSONObject else { return false }
        return hooks.values.contains { entries in
            (entries as? [JSONObject])?.contains(where: isNotchiEntry) == true
        }
    }

    func install(_ kind: AgentKind) throws {
        try writeScript()
        var config = try readConfig(kind)
        var hooks = config["hooks"] as? JSONObject ?? [:]
        for event in Self.events(for: kind) {
            var entries = (hooks[event] as? [JSONObject] ?? []).filter { !isNotchiEntry($0) }
            var hook: JSONObject = ["type": "command", "command": command(for: kind)]
            if kind == .gemini { hook["name"] = "notchi" }
            entries.append(["hooks": [hook]])
            hooks[event] = entries
        }
        config["hooks"] = hooks
        try writeConfig(config, for: kind)
    }

    func uninstall(_ kind: AgentKind) throws {
        guard FileManager.default.fileExists(atPath: configURL(for: kind).path) else { return }
        var config = try readConfig(kind)
        guard var hooks = config["hooks"] as? JSONObject else { return }
        for (event, value) in hooks {
            guard let entries = value as? [JSONObject] else { continue }
            let kept = entries.filter { !isNotchiEntry($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        config["hooks"] = hooks.isEmpty ? nil : hooks
        try writeConfig(config, for: kind)
    }

    /// The script the hooks run. Rewritten at every launch, so it follows Notchi's own changes.
    func writeScript() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.inbox, withIntermediateDirectories: true)
        try Self.script.write(to: paths.hookScript, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.hookScript.path)
    }

    /// Marks Notchi as running (or not), which the script checks before dropping anything.
    func setRunning(_ running: Bool) {
        if running {
            try? FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
            try? String(ProcessInfo.processInfo.processIdentifier).write(to: paths.pidFile, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: paths.pidFile)
        }
    }

    // MARK: Private

    private static let marker = "notchi-agent-hook"

    private static let script = """
        #!/bin/sh
        # Installed by Notchi: hands one coding-agent hook event to Notchi, which shows it in the notch.
        # Usage: notchi-agent-hook <claude|codex|gemini>, with the hook's JSON on stdin.
        # Prints nothing and always succeeds, so the agent carries on as if it weren't there.
        dir="$(dirname "$0")"
        pid=$(cat "$dir/notchi.pid" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
          tmp="$dir/Inbox/.$1-$$.tmp"
          cat > "$tmp" 2>/dev/null && mv "$tmp" "$dir/Inbox/$1-$$-$(date +%s).json" 2>/dev/null
        else
          cat > /dev/null
        fi
        exit 0

        """

    private func command(for kind: AgentKind) -> String {
        "'\(paths.hookScript.path)' \(kind.rawValue)"
    }

    private func isNotchiEntry(_ entry: JSONObject) -> Bool {
        entry.objects("hooks").contains { $0.string("command")?.contains(Self.marker) == true }
    }

    private func readConfig(_ kind: AgentKind) throws -> JSONObject {
        let url = configURL(for: kind)
        guard let data = try? Data(contentsOf: url) else { return [:] }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = JSONObject.decode(data) else { throw InstallError.unreadableConfig(url) }
        return object
    }

    private func writeConfig(_ config: JSONObject, for kind: AgentKind) throws {
        let url = configURL(for: kind)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = url.appendingPathExtension("notchi-backup")
        if fileManager.fileExists(atPath: url.path), !fileManager.fileExists(atPath: backup.path) {
            try fileManager.copyItem(at: url, to: backup)
        }
        var data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(UInt8(ascii: "\n"))
        try data.write(to: url, options: .atomic)
    }
}
