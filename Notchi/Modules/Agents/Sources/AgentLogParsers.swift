import Foundation

/// Decoded JSON object, as the agents write it.
typealias JSONObject = [String: Any]

extension JSONObject {
    static func decode(_ data: some DataProtocol) -> JSONObject? {
        (try? JSONSerialization.jsonObject(with: Data(data))) as? JSONObject
    }

    func string(_ key: String) -> String? { AgentToolDescriber.string(self[key]) }
    func object(_ key: String) -> JSONObject? { self[key] as? JSONObject }
    func objects(_ key: String) -> [JSONObject] { self[key] as? [JSONObject] ?? [] }
}

/// Reads ISO 8601 timestamps with or without fractional seconds.
enum AgentDate {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let whole = ISO8601DateFormatter()

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fractional.date(from: string) ?? whole.date(from: string)
    }

    /// Milliseconds since 1970, as Claude Code stores them.
    static func milliseconds(_ value: Any?) -> Date? {
        (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
    }
}

// MARK: - Claude Code

/// Claude Code keeps one file per running session in `~/.claude/sessions/<pid>.json`, with its
/// status (`busy`, `idle`, and what it's waiting for), and the conversation in
/// `~/.claude/projects/<folder>/<session id>.jsonl`.
enum ClaudeCodeLog {
    struct Status: Equatable {
        var pid: Int32
        var sessionID: String
        var title: String?
        var cwd: String?
        var isBusy: Bool
        /// What the session waits on, while it does (a permission prompt, a question).
        var waitingFor: String?
        var changedAt: Date
    }

    static func status(from object: JSONObject) -> Status? {
        guard let sessionID = object.string("sessionId"), let pid = (object["pid"] as? NSNumber)?.int32Value else { return nil }
        // Spare sessions are started ahead of time by the desktop app and aren't doing anything yet.
        if object["spare"] != nil { return nil }
        // Only names someone chose; derived ones are the folder name, which `AgentSession` uses anyway.
        let nameSource = object.string("nameSource")
        let title = nameSource == nil || nameSource == "user" || nameSource == "peer" ? object.string("name") : nil
        let waiting = object.string("waitingFor").flatMap { $0.isEmpty ? nil : $0 }
        return Status(
            pid: pid,
            sessionID: sessionID,
            title: title,
            cwd: object.string("cwd"),
            isBusy: object.string("status") == "busy" || waiting != nil,
            waitingFor: waiting,
            changedAt: AgentDate.milliseconds(object["statusUpdatedAt"]) ?? AgentDate.milliseconds(object["updatedAt"]) ?? Date()
        )
    }

    /// What a status change means, given the one before (nil if the session is new to Notchi).
    static func events(from status: Status, previous: Status?) -> [AgentEvent] {
        var events: [AgentEvent] = []
        if previous == nil || previous?.title != status.title || previous?.cwd != status.cwd {
            events.append(.seen(title: status.title, cwd: status.cwd))
        }
        let wasBusy = previous?.isBusy ?? false
        if status.isBusy && !wasBusy { events.append(.turnStarted) }
        if let waiting = status.waitingFor, waiting != previous?.waitingFor {
            events.append(.needsInput(waitingText(waiting)))
        } else if status.waitingFor == nil, previous?.waitingFor != nil, status.isBusy {
            events.append(.thinking)
        }
        if !status.isBusy && wasBusy { events.append(.turnEnded(.success)) }
        return events
    }

    /// "permission" → "Needs your permission".
    static func waitingText(_ waitingFor: String) -> String {
        let lower = waitingFor.lowercased()
        if lower.contains("permission") || lower.contains("approval") { return "Needs your permission" }
        if lower.contains("input") || lower.contains("question") || lower.contains("answer") { return "Has a question for you" }
        return waitingFor.prefix(1).uppercased() + waitingFor.dropFirst()
    }

    /// One transcript line. Phase changes come from the status file; the transcript adds the
    /// steps and the plan.
    static func events(fromTranscript object: JSONObject) -> [AgentEvent] {
        // Subagents' own work stays inside their "Subagent:" step.
        if object["isSidechain"] as? Bool == true { return [] }
        let content = object.object("message")?["content"] as? [JSONObject] ?? []
        switch object.string("type") {
        case "assistant":
            return content.compactMap { block in
                guard block.string("type") == "tool_use", let name = block.string("name") else { return nil }
                return AgentToolDescriber.event(tool: name, input: block.object("input") ?? [:])
            }
        case "user":
            return content.contains { $0.string("type") == "tool_result" } ? [.toolFinished] : []
        default:
            return []
        }
    }
}

// MARK: - Codex

/// Codex writes each session to `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<id>.jsonl`: turn
/// boundaries, tool calls and approval requests, one JSON object per line.
enum CodexLog {
    /// The session id at the end of a rollout file's name.
    static func sessionID(fromFileName name: String) -> String? {
        guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { return nil }
        let stem = name.dropLast(".jsonl".count)
        // rollout-2026-10-23T22-36-38-<uuid>: the uuid is the last five dash-separated parts.
        let parts = stem.split(separator: "-")
        guard parts.count > 5 else { return nil }
        return parts.suffix(5).joined(separator: "-")
    }

    static func events(from object: JSONObject) -> [AgentEvent] {
        let payload = object.object("payload") ?? [:]
        switch object.string("type") {
        case "session_meta":
            return [.seen(title: nil, cwd: payload.string("cwd"))]
        case "event_msg":
            return eventMessage(payload)
        case "response_item":
            return responseItem(payload)
        default:
            return []
        }
    }

    private static func eventMessage(_ payload: JSONObject) -> [AgentEvent] {
        switch payload.string("type") {
        case "task_started", "turn_started": return [.turnStarted]
        case "task_complete", "turn_complete": return [.turnEnded(.success)]
        case "turn_aborted": return [.turnEnded(.interrupted)]
        case "error": return [.turnEnded(.failure)]
        case "exec_approval_request": return [.needsInput("Wants to run a command")]
        case "apply_patch_approval_request": return [.needsInput("Wants to edit files")]
        case "request_user_input", "elicitation_request", "request_permissions": return [.needsInput("Has a question for you")]
        case "item_completed":
            // In code mode one script runs many commands; each finished one is the latest step.
            guard let item = payload.object("item") else { return [] }
            switch item.string("type") {
            case "CommandExecution":
                let command = (item["command"] as? [String])?.last ?? item.string("command")
                return [.toolStarted(AgentToolDescriber.step(tool: "exec_command", input: ["command": command as Any]))]
            case "FileChange":
                return [.toolStarted(AgentToolDescriber.step(tool: "FileChange", input: item))]
            default:
                return []
            }
        default:
            return []
        }
    }

    private static func responseItem(_ payload: JSONObject) -> [AgentEvent] {
        switch payload.string("type") {
        case "function_call":
            guard let name = payload.string("name") else { return [] }
            let arguments = payload.string("arguments").flatMap { JSONObject.decode(Data($0.utf8)) } ?? [:]
            return AgentToolDescriber.event(tool: name, input: arguments).map { [$0] } ?? []
        case "custom_tool_call":
            guard let name = payload.string("name") else { return [] }
            return AgentToolDescriber.event(tool: name, input: ["input": payload.string("input") as Any]).map { [$0] } ?? []
        case "local_shell_call":
            let command = (payload.object("action")?["command"] as? [String])?.last
            return [.toolStarted(AgentToolDescriber.step(tool: "local_shell", input: ["command": command as Any]))]
        case "function_call_output", "custom_tool_call_output", "local_shell_call_output":
            return [.toolFinished]
        default:
            return []
        }
    }
}

// MARK: - Gemini CLI

/// Gemini CLI keeps each chat in `~/.gemini/tmp/<project>/chats/session-<time>-<id>.jsonl`: a header
/// line, then updates that set the whole message list (`{"$set": {"messages": […]}}`).
enum GeminiLog {
    static func events(from object: JSONObject) -> [AgentEvent] {
        if let set = object.object("$set"), let last = set.objects("messages").last {
            return events(fromMessage: last)
        }
        // A line that is a message itself.
        if object["content"] != nil || object["toolCalls"] != nil, object.string("type") != nil {
            return events(fromMessage: object)
        }
        return []
    }

    /// What the newest message says about the turn.
    static func events(fromMessage message: JSONObject) -> [AgentEvent] {
        switch message.string("type") {
        case "user":
            return [.turnStarted]
        case "gemini", "model":
            let calls = message.objects("toolCalls")
            guard let call = calls.last(where: { !isSettled($0) }) ?? calls.last else {
                return [.turnEnded(.success)]
            }
            if call.string("status") == "awaiting_approval" { return [.needsInput("Needs your permission")] }
            if isSettled(call) { return [.toolFinished] }
            let name = call.string("name") ?? "tool"
            return [AgentToolDescriber.event(tool: name, input: call.object("args") ?? [:]) ?? .thinking]
        case "error":
            return [.turnEnded(.failure)]
        default:
            return []
        }
    }

    private static func isSettled(_ call: JSONObject) -> Bool {
        ["success", "error", "cancelled", "canceled"].contains(call.string("status") ?? "")
    }
}

// MARK: - Hooks

/// Events the agents hand to hooks (Notchi's hook script drops each one in its inbox). Claude Code
/// and Codex share event names; Gemini CLI has its own.
enum AgentHookPayload {
    static func update(kind: AgentKind, object: JSONObject, at date: Date) -> [AgentUpdate] {
        guard let sessionID = object.string("session_id") ?? object.string("sessionId"),
              let name = object.string("hook_event_name") else { return [] }
        var events: [AgentEvent] = [.seen(title: nil, cwd: object.string("cwd"))]
        events += self.events(name: name, object: object)
        return events.map { AgentUpdate(kind: kind, sessionID: sessionID, date: date, event: $0) }
    }

    static func events(name: String, object: JSONObject) -> [AgentEvent] {
        let tool = object.string("tool_name") ?? "tool"
        let input = object.object("tool_input") ?? [:]
        switch name {
        case "UserPromptSubmit", "BeforeAgent":
            return [.turnStarted]
        case "PreToolUse", "BeforeTool":
            return AgentToolDescriber.event(tool: tool, input: input).map { [$0] } ?? []
        case "PostToolUse", "PostToolUseFailure", "AfterTool":
            return [.toolFinished]
        case "PermissionRequest":
            return [.needsInput("Approve: \(AgentToolDescriber.step(tool: tool, input: input).text)")]
        case "Notification":
            let type = object.string("notification_type")?.lowercased() ?? ""
            let message = object.string("message") ?? ""
            // Claude's "waiting for your input" comes a minute after a request ends: not a question.
            if type == "idle_prompt" || message.lowercased().contains("waiting for your input") { return [] }
            if type.contains("permission") || type.contains("elicitation") || message.lowercased().contains("permission") {
                return [.needsInput(message.isEmpty ? "Needs your permission" : AgentToolDescriber.clip(message, 80))]
            }
            return []
        case "PreCompact", "PreCompress":
            return [.toolStarted(AgentStep(symbol: "rectangle.compress.vertical", text: "Compacting the conversation"))]
        case "Stop", "AfterAgent":
            return [.turnEnded(.success)]
        case "StopFailure":
            return [.turnEnded(.failure)]
        case "Interrupt":
            return [.turnEnded(.interrupted)]
        case "SessionEnd":
            return [.ended]
        default:
            return []
        }
    }
}
