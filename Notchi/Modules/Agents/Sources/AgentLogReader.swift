import Foundation

/// Where the agents keep their sessions, and where Notchi's hook script drops events. Tests point
/// `home` and `support` at a throwaway folder.
struct AgentPaths: Sendable {
    var home: URL
    /// Notchi's own folder for agents: the hook script, its inbox and the running-app marker.
    var support: URL

    static let standard = AgentPaths(
        home: FileManager.default.homeDirectoryForCurrentUser,
        support: URL.applicationSupportDirectory.appending(path: "Notchi/Agents", directoryHint: .isDirectory)
    )

    var claudeSessions: URL { home.appending(path: ".claude/sessions", directoryHint: .isDirectory) }
    var claudeProjects: URL { home.appending(path: ".claude/projects", directoryHint: .isDirectory) }
    var codexSessions: URL { home.appending(path: ".codex/sessions", directoryHint: .isDirectory) }
    var geminiChats: URL { home.appending(path: ".gemini/tmp", directoryHint: .isDirectory) }
    var inbox: URL { support.appending(path: "Inbox", directoryHint: .isDirectory) }
    /// Holds Notchi's process id while it runs, so the hook script drops nothing when it doesn't.
    var pidFile: URL { support.appending(path: "notchi.pid") }
    var hookScript: URL { support.appending(path: "notchi-agent-hook") }

    /// Everything to watch for changes.
    var watched: [URL] { [claudeSessions, claudeProjects, codexSessions, geminiChats, inbox] }
}

/// Reads the agents' own session files, and events from Notchi's hooks, into `AgentUpdate`s.
///
/// Logs are only ever appended to, so each is read from where the last read stopped. Runs off the
/// main thread: a busy transcript can grow by hundreds of kilobytes a minute.
actor AgentLogReader {
    private let paths: AgentPaths
    private let fileManager = FileManager.default
    /// Agents whose steps come from their logs. Once an agent's hooks are installed they report
    /// the steps instead. Claude Code's status files are read either way: they're how Notchi knows a
    /// session is alive.
    private var passive: Set<AgentKind> = Set(AgentKind.allCases)

    /// How far each log has been read, and a partial last line waiting for the rest.
    private var tails: [String: (offset: UInt64, remainder: Data)] = [:]
    /// Claude Code: the last status per status file, and which session each transcript belongs to.
    private var claudeStatuses: [String: ClaudeCodeLog.Status] = [:]
    private var claudeTranscripts: [String: String] = [:]
    /// Codex and Gemini: when each session's log last changed, to retire ones that went quiet.
    private var lastWrite: [String: (kind: AgentKind, sessionID: String, date: Date)] = [:]
    private var runningSessions: Set<String> = []

    /// How much of a log to read when a session is first found: enough for the current request.
    private let initialTail: UInt64 = 512 * 1024
    /// Claude Code transcripts carry whole tool results and images, so a long request's plan can be
    /// megabytes back. Only lines about tools are decoded.
    private let claudeInitialTail: UInt64 = 32 * 1024 * 1024
    private static func isToolLine(_ line: Data) -> Bool {
        line.range(of: Data(#""tool_use""#.utf8)) != nil || line.range(of: Data(#""tool_result""#.utf8)) != nil
    }
    /// Codex and Gemini sessions changed this recently are picked up at launch.
    private let recentWindow: TimeInterval = 30 * 60

    /// The watched folders with symlinks resolved, as FSEvents reports paths (`/private/var/…`, not `/var/…`).
    private let roots: (claudeSessions: String, claudeProjects: String, codex: String, gemini: String, inbox: String)

    init(paths: AgentPaths = .standard) {
        self.paths = paths
        roots = (
            Self.canonical(paths.claudeSessions).path, Self.canonical(paths.claudeProjects).path,
            Self.canonical(paths.codexSessions).path, Self.canonical(paths.geminiChats).path, Self.canonical(paths.inbox).path
        )
    }

    func setPassive(_ kinds: Set<AgentKind>) {
        passive = kinds
    }

    // MARK: Scanning

    /// Everything running (or recently active) when Notchi starts. Old hook events are dropped.
    func scan() -> [AgentUpdate] {
        clearInbox()
        var updates: [AgentUpdate] = []
        for file in contents(of: paths.claudeSessions) where file.pathExtension == "json" {
            updates += claudeStatusChanged(at: file)
        }
        let cutoff = Date().addingTimeInterval(-recentWindow)
        if passive.contains(.codex) {
            for file in recentFiles(under: paths.codexSessions, since: cutoff) where file.pathExtension == "jsonl" {
                updates += codexChanged(at: file)
            }
        }
        if passive.contains(.gemini) {
            for file in recentFiles(under: paths.geminiChats, since: cutoff) where isGeminiChat(file) {
                updates += geminiChanged(at: file)
            }
        }
        return updates
    }

    /// Files FSEvents says changed.
    func changed(_ changedPaths: [String]) -> [AgentUpdate] {
        var updates: [AgentUpdate] = []
        var inboxChanged = false
        for url in Set(changedPaths.map { Self.canonical(URL(filePath: $0)) }).sorted(by: { $0.path < $1.path }) {
            let path = url.path
            if path.hasPrefix(roots.inbox) {
                inboxChanged = true
            } else if path.hasPrefix(roots.claudeSessions), url.pathExtension == "json" {
                updates += claudeStatusChanged(at: url)
            } else if path.hasPrefix(roots.claudeProjects), url.pathExtension == "jsonl", passive.contains(.claude) {
                updates += claudeTranscriptChanged(at: url)
            } else if path.hasPrefix(roots.codex), url.pathExtension == "jsonl", passive.contains(.codex) {
                updates += codexChanged(at: url)
            } else if path.hasPrefix(roots.gemini), isGeminiChat(url), passive.contains(.gemini) {
                updates += geminiChanged(at: url)
            }
        }
        if inboxChanged { updates += readInbox() }
        return updates
    }

    /// Retires sessions whose process is gone, or whose log went quiet mid-request (an agent killed
    /// without a chance to say so). Called now and then while something runs.
    func sweep(now: Date = Date()) -> [AgentUpdate] {
        var updates: [AgentUpdate] = []
        for (file, status) in claudeStatuses where !Self.isAlive(status.pid) {
            claudeStatuses[file] = nil
            updates.append(AgentUpdate(kind: .claude, sessionID: status.sessionID, date: now, event: .ended))
        }
        for (file, entry) in lastWrite {
            let id = AgentSession.id(kind: entry.kind, sessionID: entry.sessionID)
            let limit: TimeInterval = entry.kind == .codex ? 20 * 60 : 10 * 60
            guard runningSessions.contains(id), now.timeIntervalSince(entry.date) > limit else { continue }
            lastWrite[file] = nil
            runningSessions.remove(id)
            updates.append(AgentUpdate(kind: entry.kind, sessionID: entry.sessionID, date: now, event: .turnEnded(.interrupted)))
        }
        return updates
    }

    // MARK: Claude Code

    private func claudeStatusChanged(at file: URL) -> [AgentUpdate] {
        let key = file.path
        let previous = claudeStatuses[key]
        guard let data = try? Data(contentsOf: file), let object = JSONObject.decode(data),
              let status = ClaudeCodeLog.status(from: object), Self.isAlive(status.pid) else {
            // Gone (the session quit) or unreadable mid-write; a removed file ends the session.
            if let previous, !fileManager.fileExists(atPath: key) {
                claudeStatuses[key] = nil
                return [AgentUpdate(kind: .claude, sessionID: previous.sessionID, date: Date(), event: .ended)]
            }
            return []
        }
        claudeStatuses[key] = status
        var updates = ClaudeCodeLog.events(from: status, previous: previous).map {
            AgentUpdate(kind: .claude, sessionID: status.sessionID, date: status.changedAt, event: $0)
        }
        // A request starting (or found running at launch): catch up on its plan and current step, from
        // the transcript lines written since it started.
        if previous?.isBusy != true, status.isBusy, passive.contains(.claude), let transcript = claudeTranscript(for: status.sessionID) {
            let since = status.changedAt.addingTimeInterval(-2)
            let lines = readNewLines(of: transcript, startingNear: claudeInitialTail, keeping: Self.isToolLine)
            updates += lines.flatMap { line -> [AgentUpdate] in
                guard let date = Self.date(of: line), date >= since else { return [] }
                return ClaudeCodeLog.events(fromTranscript: line).map {
                    AgentUpdate(kind: .claude, sessionID: status.sessionID, date: date, event: $0)
                }
            }
        }
        return updates
    }

    private func claudeTranscriptChanged(at file: URL) -> [AgentUpdate] {
        let stem = file.deletingPathExtension().lastPathComponent
        guard let sessionID = claudeTranscripts[file.path]
            ?? claudeStatuses.values.first(where: { $0.sessionID == stem })?.sessionID else { return [] }
        claudeTranscripts[file.path] = sessionID
        // Only while the session is busy: an idle session's transcript changes are bookkeeping.
        let busy = claudeStatuses.values.contains { $0.sessionID == sessionID && $0.isBusy }
        let lines = readNewLines(of: file, startingNear: initialTail, keeping: Self.isToolLine)
        guard busy else { return [] }
        return lines.flatMap { line in
            ClaudeCodeLog.events(fromTranscript: line).map {
                AgentUpdate(kind: .claude, sessionID: sessionID, date: Self.date(of: line) ?? Date(), event: $0)
            }
        }
    }

    /// `~/.claude/projects/<folder>/<session id>.jsonl`, found once per session.
    private func claudeTranscript(for sessionID: String) -> URL? {
        if let known = claudeTranscripts.first(where: { $0.value == sessionID })?.key { return URL(filePath: known) }
        for folder in contents(of: paths.claudeProjects) {
            let candidate = folder.appending(path: "\(sessionID).jsonl")
            if fileManager.fileExists(atPath: candidate.path) {
                claudeTranscripts[candidate.path] = sessionID
                return candidate
            }
        }
        return nil
    }

    // MARK: Codex and Gemini

    private func codexChanged(at file: URL) -> [AgentUpdate] {
        guard let sessionID = CodexLog.sessionID(fromFileName: file.lastPathComponent) else { return [] }
        let lines = readNewLines(of: file, startingNear: initialTail)
        return track(lines.flatMap { line in
            CodexLog.events(from: line).map {
                AgentUpdate(kind: .codex, sessionID: sessionID, date: Self.date(of: line) ?? Date(), event: $0)
            }
        }, file: file, kind: .codex, sessionID: sessionID)
    }

    private func geminiChanged(at file: URL) -> [AgentUpdate] {
        let sessionID = file.deletingPathExtension().lastPathComponent
        // The project's folder is named after it ("my-app"), unless it's an older hashed one.
        let project = file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        let title = project.count >= 40 ? nil : project
        // Each update repeats the whole conversation, so only the newest line matters.
        guard let line = readNewLines(of: file, startingNear: initialTail).last else { return [] }
        let date = AgentDate.parse(line.object("$set")?.string("lastUpdated")) ?? Self.date(of: line) ?? Date()
        let events = [AgentEvent.seen(title: title, cwd: nil)] + GeminiLog.events(from: line)
        return track(events.map { AgentUpdate(kind: .gemini, sessionID: sessionID, date: date, event: $0) },
                     file: file, kind: .gemini, sessionID: sessionID)
    }

    /// Notes which sessions are mid-request and when their log last moved, for `sweep`.
    private func track(_ updates: [AgentUpdate], file: URL, kind: AgentKind, sessionID: String) -> [AgentUpdate] {
        guard !updates.isEmpty else { return updates }
        lastWrite[file.path] = (kind, sessionID, Date())
        let id = AgentSession.id(kind: kind, sessionID: sessionID)
        for update in updates {
            switch update.event {
            case .turnStarted, .toolStarted, .thinking, .needsInput: runningSessions.insert(id)
            case .turnEnded, .ended: runningSessions.remove(id)
            default: break
            }
        }
        return updates
    }

    private func isGeminiChat(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("session-") && ["json", "jsonl"].contains(url.pathExtension)
            && url.deletingLastPathComponent().lastPathComponent == "chats"
    }

    // MARK: Hook inbox

    /// Reads and removes the events the hook script dropped, oldest first. File names start with the
    /// agent: `claude-1234-1730000000.json`.
    private func readInbox() -> [AgentUpdate] {
        let files = contents(of: paths.inbox, keys: [.creationDateKey])
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .map { ($0, (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()) }
            .sorted { $0.1 < $1.1 }
        var updates: [AgentUpdate] = []
        for (file, created) in files {
            defer { try? fileManager.removeItem(at: file) }
            let prefix = file.lastPathComponent.split(separator: "-").first.map(String.init) ?? ""
            guard let kind = AgentKind(rawValue: prefix), let data = try? Data(contentsOf: file),
                  let object = JSONObject.decode(data) else { continue }
            updates += AgentHookPayload.update(kind: kind, object: object, at: created)
        }
        return updates
    }

    private func clearInbox() {
        for file in contents(of: paths.inbox) { try? fileManager.removeItem(at: file) }
    }

    // MARK: Files

    /// Complete new lines since the last read, decoded (those `keeping` lets through). A file read
    /// for the first time starts `startingNear` bytes from its end (dropping the cut-off first line).
    private func readNewLines(of file: URL, startingNear tailSize: UInt64, keeping keep: (Data) -> Bool = { _ in true }) -> [JSONObject] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        var state = tails[file.path] ?? (offset: size > tailSize ? size - tailSize : 0, remainder: Data())
        let isFirstRead = tails[file.path] == nil
        // Shorter than last time: rewritten from scratch.
        if size < state.offset { state = (0, Data()) }
        guard size > state.offset, (try? handle.seek(toOffset: state.offset)) != nil,
              let chunk = try? handle.readToEnd() else { return [] }
        var data = state.remainder + chunk
        var remainder = Data()
        if data.last != UInt8(ascii: "\n") {
            // Keep the unfinished last line for next time.
            if let lastBreak = data.lastIndex(of: UInt8(ascii: "\n")) {
                remainder = data[(lastBreak + 1)...]
                data = data[...lastBreak]
            } else {
                remainder = data
                data = Data()
            }
        }
        tails[file.path] = (size, Data(remainder))
        var lines = data.split(separator: UInt8(ascii: "\n"))
        if isFirstRead && state.offset > 0, !lines.isEmpty { lines.removeFirst() }
        return lines.filter(keep).compactMap { JSONObject.decode($0) }
    }

    private func contents(of folder: URL, keys: [URLResourceKey] = []) -> [URL] {
        ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []).map(Self.canonical)
    }

    private func recentFiles(under folder: URL, since cutoff: Date) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return [] }
        var found: [(URL, Date)] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            if values?.isRegularFile == true, let date = values?.contentModificationDate, date > cutoff { found.append((Self.canonical(url), date)) }
        }
        return found.sorted { $0.1 < $1.1 }.map(\.0)
    }

    private static func date(of line: JSONObject) -> Date? {
        AgentDate.parse(line.string("timestamp"))
    }

    /// One spelling per file, so a log isn't read twice under two names. The folder is resolved
    /// (it exists even when the file was just removed), the name kept.
    private static func canonical(_ url: URL) -> URL {
        url.deletingLastPathComponent().resolvingSymlinksInPath().appending(path: url.lastPathComponent)
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
