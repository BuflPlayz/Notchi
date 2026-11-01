import Foundation

/// Turns a tool call, as any of the agents name it, into what Notchi shows: a one-line step
/// ("Editing NotchShape.swift"), a plan update, or a question for the user.
///
/// Claude Code, Codex and Gemini name the same work differently (`Edit`, `apply_patch`, `replace`),
/// so tools are matched by family rather than one by one. Unknown tools still read sensibly:
/// "Using Roblox Studio".
enum AgentToolDescriber {
    /// `input` is the tool's arguments as decoded JSON.
    static func event(tool: String, input: [String: Any]) -> AgentEvent? {
        let name = tool.lowercased()

        // Plans first: they're progress, not steps.
        if let plan = plan(tool: name, input: input) { return plan }

        switch name {
        case "askuserquestion", "ask_user", "request_user_input":
            return .needsInput(firstQuestion(in: input) ?? "Has a question for you")
        case "exitplanmode", "exit_plan_mode":
            return .needsInput("Plan ready for your review")
        default:
            return .toolStarted(step(tool: tool, input: input))
        }
    }

    static func step(tool: String, input: [String: Any]) -> AgentStep {
        let name = tool.lowercased()
        let file = fileName(in: input)

        switch name {
        case "bash", "shell", "exec_command", "run_shell_command", "local_shell", "commandexecution", "unified_exec":
            // Claude Code describes its own commands ("Run the unit tests"): the best label there is.
            if let description = string(input["description"]), !description.isEmpty {
                return AgentStep(symbol: "terminal", text: description)
            }
            let command = string(input["command"]) ?? string(input["cmd"]) ?? (input["command"] as? [String])?.joined(separator: " ")
            return AgentStep(symbol: "terminal", text: command.map { "Running \(commandSummary($0))" } ?? "Running a command")
        case "edit", "multiedit", "replace", "str_replace", "str_replace_editor", "apply_patch", "filechange", "notebookedit", "edit_file":
            let target = file ?? string(input["input"]).flatMap(patchedFile) ?? string(input["patch"]).flatMap(patchedFile)
            return AgentStep(symbol: "pencil", text: target.map { "Editing \($0)" } ?? "Editing files")
        case "write", "write_file", "create", "create_file":
            return AgentStep(symbol: "doc.badge.plus", text: file.map { "Writing \($0)" } ?? "Writing a file")
        case "read", "read_file", "read_many_files", "view", "view_image", "notebookread":
            return AgentStep(symbol: "doc.text", text: file.map { "Reading \($0)" } ?? "Reading files")
        case "grep", "glob", "search_file_content", "search", "find", "list_directory", "ls", "codebase_search", "file_search":
            let pattern = string(input["pattern"]) ?? string(input["query"]) ?? string(input["regex"])
            return AgentStep(symbol: "magnifyingglass", text: pattern.map { "Searching for “\(clip($0, 28))”" } ?? "Searching the code")
        case "webfetch", "web_fetch", "fetch":
            let host = string(input["url"]).flatMap { URL(string: $0)?.host() }
            return AgentStep(symbol: "globe", text: host.map { "Reading \($0)" } ?? "Reading a web page")
        case "websearch", "web_search", "google_web_search", "web_search_preview":
            let query = string(input["query"])
            return AgentStep(symbol: "globe", text: query.map { "Searching the web for “\(clip($0, 24))”" } ?? "Searching the web")
        case "task", "agent", "spawn_agent", "subagent", "delegate":
            let what = string(input["description"]) ?? string(input["subagent_type"])
            return AgentStep(symbol: "person.2", text: what.map { "Subagent: \($0)" } ?? "Running a subagent")
        case "skill":
            let skill = string(input["skill"]) ?? string(input["name"])
            return AgentStep(symbol: "wand.and.stars", text: skill.map { "Using the \($0) skill" } ?? "Using a skill")
        case "exec":
            // Codex's code mode: JavaScript calling its tools. Show the first command it runs.
            if let code = string(input["input"]) ?? string(input["code"]), let command = firstCommand(inScript: code) {
                return AgentStep(symbol: "terminal", text: "Running \(commandSummary(command))")
            }
            return AgentStep(symbol: "chevron.left.forwardslash.chevron.right", text: "Running code")
        default:
            break
        }

        if name.hasPrefix("mcp__") {
            // mcp__server__tool: name the server, unless it's an opaque id.
            let parts = tool.components(separatedBy: "__").dropFirst()
            let server = parts.first.map(humanized) ?? "a tool"
            let looksLikeID = server.count > 24 || server.filter(\.isNumber).count > 6
            let label = looksLikeID ? (parts.last.map(humanized) ?? "a tool") : server
            return AgentStep(symbol: "puzzlepiece.extension", text: "Using \(label)")
        }
        return AgentStep(symbol: "hammer", text: "Using \(humanized(tool))")
    }

    // MARK: Plans

    private static func plan(tool name: String, input: [String: Any]) -> AgentEvent? {
        switch name {
        case "todowrite", "write_todos":
            // Claude Code: {todos: [{content, status, activeForm}]}; Gemini: {todos: [{description, status}]}.
            guard let todos = input["todos"] as? [[String: Any]] else { return nil }
            return .planUpdated(AgentPlan(items: todos.compactMap { todo in
                let status = AgentPlan.status(string(todo["status"]))
                // While active, Claude's "activeForm" reads better: "Running tests" not "Run tests".
                let title = (status == .active ? string(todo["activeForm"]) : nil)
                    ?? string(todo["content"]) ?? string(todo["description"]) ?? string(todo["title"])
                return title.map { AgentPlan.Item(title: $0, status: status) }
            }))
        case "update_plan", "mcp__ccd_turn__update_plan":
            // Codex: {plan: [{step, status}]}. The Claude app: {items: [{content, status}]}, or an edit.
            if let steps = (input["plan"] ?? input["items"]) as? [[String: Any]] {
                return .planUpdated(AgentPlan(items: steps.compactMap { step in
                    (string(step["step"]) ?? string(step["content"]) ?? string(step["title"]))
                        .map { AgentPlan.Item(title: $0, status: AgentPlan.status(string(step["status"]))) }
                }))
            }
            if input["advance"] as? Bool == true { return .planEdited(.advance) }
            let done = (input["done"] as? [Any])?.compactMap(int).map { $0 - 1 } ?? []
            let start = int(input["start"] as Any).map { $0 - 1 }
            return done.isEmpty && start == nil ? nil : .planEdited(.mark(done: done, start: start))
        case "taskcreate":
            // Claude Code's tasks are numbered in the order they're made; the result carries the id.
            guard let subject = string(input["subject"]) ?? string(input["title"]) else { return nil }
            return .planEdited(.append(AgentPlan.Item(title: subject, status: .pending)))
        case "taskupdate":
            guard let key = string(input["taskId"]) ?? string(input["id"]) else { return nil }
            let word = string(input["status"])
            return .planEdited(.setStatus(key: key, status: word == "deleted" ? nil : AgentPlan.status(word)))
        default:
            return nil
        }
    }

    // MARK: Helpers

    /// "xcodebuild" for `cd ~/x && FOO=1 xcodebuild -project…`; "git status" for `git status --short`.
    static func commandSummary(_ command: String) -> String {
        let lastPart = command
            .components(separatedBy: "&&").last?
            .components(separatedBy: "|").first ?? command
        var words = lastPart.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = words.first, first.contains("=") || ["sudo", "env", "time", "exec", "command"].contains(first) {
            words.removeFirst()
        }
        guard let first = words.first else { return "a command" }
        let program = URL(filePath: first.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))).lastPathComponent
        let withSubcommand: Set = ["git", "npm", "pnpm", "yarn", "bun", "cargo", "swift", "go", "docker", "gh", "brew", "make", "uv", "pip", "pip3", "npx", "kubectl", "deno", "dotnet", "flutter", "pod"]
        if withSubcommand.contains(program), words.count > 1, let sub = words.dropFirst().first,
           sub.first?.isLetter == true, !sub.contains("/") {
            return clip("\(program) \(sub)", 30)
        }
        return clip(program, 30)
    }

    /// The first `exec_command` in a Codex code-mode script.
    private static func firstCommand(inScript code: String) -> String? {
        guard let match = code.firstMatch(of: /cmd\s*:\s*"((?:[^"\\]|\\.)*)"/) else { return nil }
        return String(match.1)
    }

    /// The file a patch touches first: `*** Update File: path`.
    private static func patchedFile(_ patch: String) -> String? {
        guard let match = patch.firstMatch(of: /\*\*\* (?:Update|Add|Delete) File: (.+)/) else { return nil }
        return URL(filePath: String(match.1).trimmingCharacters(in: .whitespaces)).lastPathComponent
    }

    private static func fileName(in input: [String: Any]) -> String? {
        for key in ["file_path", "path", "absolute_path", "notebook_path", "file", "filename", "target_file"] {
            if let path = string(input[key]), !path.isEmpty { return URL(filePath: path).lastPathComponent }
        }
        if let paths = input["paths"] as? [String], let first = paths.first {
            let name = URL(filePath: first).lastPathComponent
            return paths.count > 1 ? "\(name) +\(paths.count - 1)" : name
        }
        // Codex's FileChange item: {changes: {path: change}}.
        if let changes = input["changes"] as? [String: Any], let first = changes.keys.sorted().first {
            let name = URL(filePath: first).lastPathComponent
            return changes.count > 1 ? "\(name) +\(changes.count - 1)" : name
        }
        return nil
    }

    private static func firstQuestion(in input: [String: Any]) -> String? {
        if let questions = input["questions"] as? [[String: Any]], let first = questions.first {
            return string(first["question"]).map { clip($0, 80) }
        }
        return string(input["question"]).map { clip($0, 80) }
    }

    /// "roblox_studio" → "Roblox Studio", "search_game_tree" → "Search game tree".
    static func humanized(_ identifier: String) -> String {
        let spaced = identifier.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        let words = spaced.split(separator: " ")
        // Two short words read like a name ("Roblox Studio"); anything else like a sentence.
        if words.count == 2 { return words.map(\.capitalized).joined(separator: " ") }
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    static func clip(_ text: String, _ length: Int) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > length ? String(line.prefix(length - 1)) + "…" : line
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    private static func int(_ value: Any) -> Int? {
        (value as? NSNumber)?.intValue ?? (value as? String).flatMap(Int.init)
    }
}
