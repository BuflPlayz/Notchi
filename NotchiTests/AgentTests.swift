import Foundation
import SwiftUI
import Testing
@testable import Notchi

/// A group with children whose activities the test sets.
@MainActor
@Observable
private final class RecordingGroup: NotchActivityGroup {
    let id = "agents"
    let title = "Agents"
    let symbol = "sparkles"
    let liveActivity: LiveActivity? = nil
    var children: [RecordingModule] = []
    var activities: [any NotchModule] { children }

    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
struct ActivityGroupTests {
    private func makeRegistry() -> (ModuleRegistry, RecordingModule, RecordingGroup) {
        let registry = ModuleRegistry(defaults: UserDefaults(suiteName: "notchi.tests.\(UUID().uuidString)")!)
        let media = RecordingModule(id: "media")
        let group = RecordingGroup()
        registry.register(group)
        registry.register(media)
        return (registry, media, group)
    }

    @Test func childrenAreActivitiesOfTheirOwn() {
        let (registry, media, group) = makeRegistry()
        let first = RecordingModule(id: "agent.claude.1")
        let second = RecordingModule(id: "agent.codex.2")
        group.children = [first, second]
        first.liveActivity = LiveActivity(priority: .active)
        second.liveActivity = LiveActivity(priority: .active)
        media.liveActivity = LiveActivity(priority: .active)

        // The group comes first, so its children win ties; the rest become bubbles.
        #expect(registry.foreground?.id == "agent.claude.1")
        #expect(registry.satelliteCandidates.map(\.id) == ["agent.codex.2", "media"])
        #expect(registry.module(withID: "agent.codex.2") === second)

        // A child that needs the user takes the middle.
        second.liveActivity = LiveActivity(priority: .urgent)
        #expect(registry.foreground?.id == "agent.codex.2")
    }

    @Test func childrenOpenTheirGroupsPage() {
        let (registry, _, group) = makeRegistry()
        group.children = [RecordingModule(id: "agent.claude.1")]
        #expect(registry.panelModuleID(for: "agent.claude.1") == "agents")
        #expect(registry.panelModuleID(for: "media") == "media")
        #expect(registry.panelModuleID(for: "nope") == nil)
        // Settings and the tabs only see the group.
        #expect(registry.modules.map(\.id) == ["agents", "media"])
    }

    @Test func disablingTheGroupHidesItsChildren() {
        let (registry, _, group) = makeRegistry()
        let child = RecordingModule(id: "agent.claude.1")
        child.liveActivity = LiveActivity(priority: .urgent)
        group.children = [child]
        registry.setEnabled(false, for: "agents")
        #expect(registry.foreground == nil)
        #expect(registry.module(withID: "agent.claude.1") == nil)
    }
}

@MainActor
struct AgentsModuleTests {
    @Test func switchingAgentsOffStopsEverything() throws {
        let root = URL.temporaryDirectory.appending(path: "NotchiAgentsModule-\(UUID().uuidString)", directoryHint: .isDirectory)
        let paths = AgentPaths(home: root.appending(path: "home"), support: root.appending(path: "support"))
        let registry = ModuleRegistry(defaults: UserDefaults(suiteName: "notchi.tests.\(UUID().uuidString)")!)
        let agents = AgentsModule(paths: paths)
        registry.register(agents)
        registry.register(RecordingModule(id: "media"))
        registry.startAll()
        // Running: the hook script hands events over while this file names a live process.
        #expect(FileManager.default.fileExists(atPath: paths.pidFile.path))
        #if DEBUG
        agents.showDebugAgent("codex:waiting")
        #expect(registry.foreground?.id == "agent.codex.debug-codex")
        #endif

        registry.setEnabled(false, for: "agents")
        #expect(!FileManager.default.fileExists(atPath: paths.pidFile.path))
        #expect(agents.sessions.isEmpty)
        #expect(registry.foreground == nil)

        registry.setEnabled(true, for: "agents")
        #expect(FileManager.default.fileExists(atPath: paths.pidFile.path))
        registry.stopAll()
    }
}

struct AgentSessionTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func aRequestRunsAndEnds() {
        var session = AgentSession(kind: .claude, sessionID: "s", cwd: "/Users/me/Code/Notchi", at: start)
        #expect(session.title == "Notchi")
        session.apply(.turnStarted, at: start)
        #expect(session.phase == .thinking)
        session.apply(.toolStarted(AgentStep(symbol: "pencil", text: "Editing A.swift")), at: start + 5)
        #expect(session.phase == .working)
        #expect(session.step?.text == "Editing A.swift")
        session.apply(.toolFinished, at: start + 6)
        #expect(session.phase == .thinking)
        session.apply(.needsInput("Needs your permission"), at: start + 7)
        #expect(session.phase == .needsInput)
        #expect(session.isRunning)
        // Hooks and logs both report the start; the second doesn't restart the clock.
        session.apply(.turnStarted, at: start + 8)
        #expect(session.turnStartedAt == start)
        session.apply(.turnEnded(.success), at: start + 30)
        #expect(session.phase == .finished)
        #expect(session.outcome == .success)
        #expect(AgentFormat.status(of: session) == "Done in 30s")
        #expect(session.toolCount == 1)
    }

    @Test func aToolWithoutAStartBeginsARequest() {
        var session = AgentSession(kind: .codex, sessionID: "s", at: start)
        session.apply(.toolStarted(AgentStep(symbol: "terminal", text: "Running git status")), at: start + 2)
        #expect(session.isRunning)
        #expect(session.turnStartedAt == start + 2)
    }

    @Test func interruptedRequestsGoQuietlyIdle() {
        var session = AgentSession(kind: .codex, sessionID: "s", at: start)
        session.apply(.turnStarted, at: start)
        session.apply(.turnEnded(.interrupted), at: start + 1)
        #expect(session.phase == .idle)
        // Ending twice changes nothing.
        session.apply(.turnEnded(.success), at: start + 2)
        #expect(session.phase == .idle)
    }

    @Test func plansAdvanceAndFinish() {
        var session = AgentSession(kind: .claude, sessionID: "s", at: start)
        session.apply(.turnStarted, at: start)
        session.apply(.planUpdated(AgentPlan(items: [
            .init(title: "One", status: .active), .init(title: "Two", status: .pending), .init(title: "Three", status: .pending),
        ])), at: start)
        session.apply(.planEdited(.advance), at: start)
        #expect(session.plan?.completed == 1)
        #expect(session.plan?.current?.title == "Two")
        session.apply(.planEdited(.mark(done: [1, 2], start: nil)), at: start)
        #expect(session.plan?.isFinished == true)
        session.apply(.turnEnded(.success), at: start + 1)
        // A finished plan doesn't follow into the next request.
        session.apply(.turnStarted, at: start + 2)
        #expect(session.plan == nil)
    }

    @Test func tasksAreNumberedLikeClaudeCodes() {
        var plan = AgentPlan(items: [])
        plan.apply(.append(.init(title: "First", status: .pending)))
        plan.apply(.append(.init(title: "Second", status: .pending)))
        plan.apply(.setStatus(key: "2", status: .active))
        #expect(plan.current?.title == "Second")
        plan.apply(.setStatus(key: "1", status: nil))
        #expect(plan.items.map(\.title) == ["Second"])
    }
}

struct AgentToolDescriberTests {
    private func step(_ tool: String, _ input: JSONObject) -> String? {
        if case .toolStarted(let step)? = AgentToolDescriber.event(tool: tool, input: input) { return step.text }
        return nil
    }

    @Test func describesEachAgentsTools() {
        #expect(step("Bash", ["command": "xcodebuild test", "description": "Run the unit tests"]) == "Run the unit tests")
        #expect(step("Bash", ["command": "cd ~/x && FOO=1 git status --short"]) == "Running git status")
        #expect(step("exec_command", ["cmd": "/usr/bin/xcodebuild -project A.xcodeproj build"]) == "Running xcodebuild")
        #expect(step("Edit", ["file_path": "/a/b/NotchShape.swift"]) == "Editing NotchShape.swift")
        #expect(step("apply_patch", ["input": "*** Begin Patch\n*** Update File: Sources/App.swift\n@@"]) == "Editing App.swift")
        #expect(step("replace", ["file_path": "/x/main.py"]) == "Editing main.py")
        #expect(step("write_file", ["file_path": "/x/README.md"]) == "Writing README.md")
        #expect(step("Grep", ["pattern": "liveActivity"]) == "Searching for “liveActivity”")
        #expect(step("WebFetch", ["url": "https://developer.apple.com/docs"]) == "Reading developer.apple.com")
        #expect(step("Task", ["description": "Explore the registry"]) == "Subagent: Explore the registry")
        #expect(step("exec", ["input": "text(await tools.exec_command({cmd:\"swift build\"}))"]) == "Running swift build")
        #expect(step("mcp__Roblox_Studio__search_game_tree", [:]) == "Using Roblox Studio")
        #expect(step("FancyTool", [:]) == "Using FancyTool")
    }

    @Test func questionsNeedTheUser() {
        let event = AgentToolDescriber.event(tool: "AskUserQuestion", input: ["questions": [["question": "Which layout?"]]])
        #expect(event == .needsInput("Which layout?"))
    }

    @Test func readsEveryKindOfPlan() {
        let todos = AgentToolDescriber.event(tool: "TodoWrite", input: ["todos": [
            ["content": "Run tests", "activeForm": "Running tests", "status": "in_progress"],
            ["content": "Ship", "activeForm": "Shipping", "status": "pending"],
        ]])
        #expect(todos == .planUpdated(AgentPlan(items: [.init(title: "Running tests", status: .active), .init(title: "Ship", status: .pending)])))

        let codex = AgentToolDescriber.event(tool: "update_plan", input: ["plan": [["step": "Read", "status": "completed"], ["step": "Write", "status": "in_progress"]]])
        #expect(codex == .planUpdated(AgentPlan(items: [.init(title: "Read", status: .done), .init(title: "Write", status: .active)])))

        #expect(AgentToolDescriber.event(tool: "mcp__ccd_turn__update_plan", input: ["advance": true]) == .planEdited(.advance))
        #expect(AgentToolDescriber.event(tool: "mcp__ccd_turn__update_plan", input: ["done": [2], "start": 4]) == .planEdited(.mark(done: [1], start: 3)))

        let gemini = AgentToolDescriber.event(tool: "write_todos", input: ["todos": [["description": "Fix bug", "status": "completed"]]])
        #expect(gemini == .planUpdated(AgentPlan(items: [.init(title: "Fix bug", status: .done)])))
    }
}

struct AgentLogParserTests {
    private func object(_ json: String) -> JSONObject { JSONObject.decode(Data(json.utf8))! }

    @Test func claudeStatusChangesBecomeEvents() {
        let busy = ClaudeCodeLog.status(from: object(#"{"pid":1,"sessionId":"abc","cwd":"/x/Notchi","name":"My task","nameSource":"user","status":"busy","statusUpdatedAt":1793561912597}"#))!
        #expect(busy.title == "My task")
        #expect(ClaudeCodeLog.events(from: busy, previous: nil) == [.seen(title: "My task", cwd: "/x/Notchi"), .turnStarted])

        var waiting = busy
        waiting.waitingFor = "permission"
        #expect(ClaudeCodeLog.events(from: waiting, previous: busy) == [.needsInput("Needs your permission")])

        var idle = busy
        idle.isBusy = false
        #expect(ClaudeCodeLog.events(from: idle, previous: busy) == [.turnEnded(.success)])

        // Spare sessions the app starts ahead of time aren't sessions yet.
        #expect(ClaudeCodeLog.status(from: object(#"{"pid":1,"sessionId":"abc","status":"idle","spare":true}"#)) == nil)
        // Derived names are just the folder name.
        let derived = ClaudeCodeLog.status(from: object(#"{"pid":1,"sessionId":"abc","name":"x","nameSource":"derived","status":"idle"}"#))
        #expect(derived?.title == nil)
    }

    @Test func claudeTranscriptsGiveSteps() {
        let line = object(#"{"type":"assistant","message":{"content":[{"type":"thinking"},{"type":"tool_use","name":"Read","input":{"file_path":"/a/Notes.md"}}]}}"#)
        #expect(ClaudeCodeLog.events(fromTranscript: line) == [.toolStarted(AgentStep(symbol: "doc.text", text: "Reading Notes.md"))])
        let result = object(#"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#)
        #expect(ClaudeCodeLog.events(fromTranscript: result) == [.toolFinished])
        let sidechain = object(#"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}"#)
        #expect(ClaudeCodeLog.events(fromTranscript: sidechain).isEmpty)
    }

    @Test func codexRolloutsGiveTurnsAndSteps() {
        #expect(CodexLog.sessionID(fromFileName: "rollout-2026-10-23T22-36-38-01a16a43-eb58-7d42-85a2-aef3fea8bb3f.jsonl") == "01a16a43-eb58-7d42-85a2-aef3fea8bb3f")
        #expect(CodexLog.events(from: object(#"{"type":"event_msg","payload":{"type":"task_started"}}"#)) == [.turnStarted])
        #expect(CodexLog.events(from: object(#"{"type":"event_msg","payload":{"type":"task_complete"}}"#)) == [.turnEnded(.success)])
        #expect(CodexLog.events(from: object(#"{"type":"event_msg","payload":{"type":"exec_approval_request"}}"#)) == [.needsInput("Wants to run a command")])
        let call = object(#"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"npm test\"}"}}"#)
        #expect(CodexLog.events(from: call) == [.toolStarted(AgentStep(symbol: "terminal", text: "Running npm test"))])
        let command = object(#"{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"CommandExecution","command":["/bin/zsh","-lc","pwd && rg --files"]}}}"#)
        #expect(CodexLog.events(from: command) == [.toolStarted(AgentStep(symbol: "terminal", text: "Running rg"))])
        #expect(CodexLog.events(from: object(#"{"type":"session_meta","payload":{"cwd":"/x/app"}}"#)) == [.seen(title: nil, cwd: "/x/app")])
    }

    @Test func geminiChatsReadTheNewestMessage() {
        let asking = object(#"{"$set":{"messages":[{"type":"user","content":"hi"}]}}"#)
        #expect(GeminiLog.events(from: asking) == [.turnStarted])
        let running = object(#"{"$set":{"messages":[{"type":"user"},{"type":"gemini","content":"","toolCalls":[{"name":"run_shell_command","status":"executing","args":{"command":"ls -la"}}]}]}}"#)
        #expect(GeminiLog.events(from: running) == [.toolStarted(AgentStep(symbol: "terminal", text: "Running ls"))])
        let approving = object(#"{"$set":{"messages":[{"type":"gemini","toolCalls":[{"name":"write_file","status":"awaiting_approval"}]}]}}"#)
        #expect(GeminiLog.events(from: approving) == [.needsInput("Needs your permission")])
        let done = object(#"{"$set":{"messages":[{"type":"gemini","content":"All set"}]}}"#)
        #expect(GeminiLog.events(from: done) == [.turnEnded(.success)])
    }

    @Test func hookPayloadsBecomeUpdates() {
        let date = Date()
        let pre = AgentHookPayload.update(kind: .claude, object: object(#"{"session_id":"s1","cwd":"/x/Notchi","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/x/A.swift"}}"#), at: date)
        #expect(pre.map(\.event) == [.seen(title: nil, cwd: "/x/Notchi"), .toolStarted(AgentStep(symbol: "pencil", text: "Editing A.swift"))])
        #expect(pre.allSatisfy { $0.sessionID == "s1" && $0.kind == .claude })

        // Claude's idle reminder isn't a question.
        let idle = AgentHookPayload.events(name: "Notification", object: object(#"{"notification_type":"idle_prompt","message":"Claude is waiting for your input"}"#))
        #expect(idle.isEmpty)
        let permission = AgentHookPayload.events(name: "Notification", object: object(#"{"message":"Claude needs your permission to use Bash"}"#))
        #expect(permission == [.needsInput("Claude needs your permission to use Bash")])

        #expect(AgentHookPayload.events(name: "BeforeAgent", object: [:]) == [.turnStarted])
        #expect(AgentHookPayload.events(name: "AfterAgent", object: [:]) == [.turnEnded(.success)])
        #expect(AgentHookPayload.events(name: "Stop", object: [:]) == [.turnEnded(.success)])
        #expect(AgentHookPayload.events(name: "SessionEnd", object: [:]) == [.ended])
    }
}

struct AgentLogReaderTests {
    private let paths: AgentPaths = {
        let root = URL.temporaryDirectory.appending(path: "NotchiAgentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return AgentPaths(home: root.appending(path: "home"), support: root.appending(path: "support"))
    }()

    private func write(_ text: String, to url: URL, append: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if append, let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: url)
        }
    }

    @Test func followsAClaudeSessionFromItsFiles() async throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let startedMs = Int(Date().timeIntervalSince1970 * 1000) - 10_000
        let status = paths.claudeSessions.appending(path: "\(pid).json")
        let transcript = paths.claudeProjects.appending(path: "-x-Notchi/sess-1.jsonl")
        let stamp = ISO8601DateFormatter().string(from: Date())
        try write(#"{"type":"assistant","timestamp":"\#(stamp)","message":{"content":[{"type":"tool_use","name":"Grep","input":{"pattern":"foo"}}]}}"# + "\n", to: transcript)
        try write(#"{"pid":\#(pid),"sessionId":"sess-1","cwd":"/x/Notchi","status":"busy","statusUpdatedAt":\#(startedMs)}"#, to: status)

        let reader = AgentLogReader(paths: paths)
        let found = await reader.scan()
        #expect(found.map(\.event) == [
            .seen(title: nil, cwd: "/x/Notchi"), .turnStarted,
            .toolStarted(AgentStep(symbol: "magnifyingglass", text: "Searching for “foo”")),
        ])

        // A new line in the transcript is the next step; half a line waits for the rest.
        try write(#"{"type":"user","timestamp":"\#(stamp)","message":{"content":[{"type":"tool_result"}]}}"# + "\n" + #"{"type":"assist"#, to: transcript, append: true)
        let next = await reader.changed([transcript.path])
        #expect(next.map(\.event) == [.toolFinished])

        try write(#"{"pid":\#(pid),"sessionId":"sess-1","cwd":"/x/Notchi","status":"idle","statusUpdatedAt":\#(startedMs + 9000)}"#, to: status)
        #expect(await reader.changed([status.path]).map(\.event) == [.turnEnded(.success)])

        try FileManager.default.removeItem(at: status)
        #expect(await reader.changed([status.path]).map(\.event) == [.ended])
    }

    @Test func readsCodexRolloutsAndTheHookInbox() async throws {
        let rollout = paths.codexSessions.appending(path: "2026/11/01/rollout-2026-11-01T10-00-00-01a16a43-eb58-7d42-85a2-aef3fea8bb3f.jsonl")
        try write(#"{"type":"session_meta","payload":{"cwd":"/x/app"}}"# + "\n" + #"{"type":"event_msg","payload":{"type":"task_started"}}"# + "\n", to: rollout)
        let reader = AgentLogReader(paths: paths)
        let found = await reader.scan()
        #expect(found.map(\.event) == [.seen(title: nil, cwd: "/x/app"), .turnStarted])
        #expect(found.first?.sessionID == "01a16a43-eb58-7d42-85a2-aef3fea8bb3f")

        // Codex hooked: its log is no longer read, and hook events come from the inbox.
        await reader.setPassive([.claude, .gemini])
        try write(#"{"type":"event_msg","payload":{"type":"task_complete"}}"# + "\n", to: rollout, append: true)
        #expect(await reader.changed([rollout.path]).isEmpty)

        let event = paths.inbox.appending(path: "codex-123-1.json")
        try write(#"{"session_id":"t1","hook_event_name":"Stop"}"#, to: event)
        let hooked = await reader.changed([event.path])
        #expect(hooked.map(\.event) == [.seen(title: nil, cwd: nil), .turnEnded(.success)])
        #expect(hooked.first?.kind == .codex)
        #expect(!FileManager.default.fileExists(atPath: event.path))
    }
}

struct AgentHookInstallerTests {
    private let paths: AgentPaths = {
        let root = URL.temporaryDirectory.appending(path: "NotchiHookTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return AgentPaths(home: root.appending(path: "home"), support: root.appending(path: "support"))
    }()

    @Test func installsBesideTheUsersOwnHooksAndRemovesOnlyNotchis() throws {
        let installer = AgentHookInstaller(paths: paths)
        let settings = installer.configURL(for: .claude)
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        try Data(original.utf8).write(to: settings)

        try installer.install(.claude)
        #expect(installer.isInstalled(.claude))
        let installed = JSONObject.decode(try Data(contentsOf: settings))!
        #expect(installed.string("model") == "opus")
        let stop = installed.object("hooks")?.objects("Stop") ?? []
        #expect(stop.count == 2)
        #expect(stop.last?.objects("hooks").first?.string("command")?.contains("notchi-agent-hook") == true)
        #expect(FileManager.default.isExecutableFile(atPath: paths.hookScript.path))
        #expect(try String(contentsOf: settings.appendingPathExtension("notchi-backup"), encoding: .utf8) == original)

        // Installing again doesn't add a second copy.
        try installer.install(.claude)
        #expect((JSONObject.decode(try Data(contentsOf: settings))?.object("hooks")?.objects("Stop") ?? []).count == 2)

        try installer.uninstall(.claude)
        #expect(!installer.isInstalled(.claude))
        let removed = JSONObject.decode(try Data(contentsOf: settings))!
        #expect(removed.object("hooks")?.objects("Stop").first?.objects("hooks").first?.string("command") == "say done")
        #expect(removed.object("hooks")?["PreToolUse"] == nil)
    }

    @Test func leavesAnUnreadableConfigAlone() throws {
        let installer = AgentHookInstaller(paths: paths)
        let settings = installer.configURL(for: .gemini)
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ // comment\n}".utf8).write(to: settings)
        #expect(throws: AgentHookInstaller.InstallError.self) { try installer.install(.gemini) }
        #expect(try String(contentsOf: settings, encoding: .utf8) == "{ // comment\n}")
    }

    @Test func theScriptDropsEventsOnlyWhileNotchiRuns() throws {
        let installer = AgentHookInstaller(paths: paths)
        try installer.writeScript()
        func run() throws {
            let process = Process()
            process.executableURL = paths.hookScript
            process.arguments = ["claude"]
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(#"{"hook_event_name":"Stop"}"#.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        try run()
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.inbox.path).isEmpty)
        installer.setRunning(true)
        try run()
        let files = try FileManager.default.contentsOfDirectory(atPath: paths.inbox.path)
        #expect(files.count == 1)
        #expect(files.first?.hasPrefix("claude-") == true)
        installer.setRunning(false)
    }
}

struct MascotSpriteTests {
    @Test func readsFilesOutOfAnAsarArchive() throws {
        let payload = Data("console.log(1)".utf8)
        let json = Data(#"{"files":{"app":{"files":{"main.js":{"size":\#(payload.count),"offset":"0"}}}}}"#.utf8)
        // Chromium pickle: payload size, JSON length, JSON padded to 4 bytes.
        let padded = json + Data(repeating: 0, count: (4 - json.count % 4) % 4)
        var archive = Data()
        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { archive.append(contentsOf: $0) } }
        append(4)
        append(UInt32(8 + padded.count))
        append(UInt32(4 + padded.count))
        append(UInt32(json.count))
        archive.append(padded)
        archive.append(payload)
        let url = URL.temporaryDirectory.appending(path: "notchi-\(UUID().uuidString).asar")
        try archive.write(to: url)

        let reader = try #require(AsarArchive(url: url))
        #expect(reader.paths { $0.hasSuffix(".js") } == ["/app/main.js"])
        #expect(reader.data(at: "/app/main.js") == payload)
    }

    @Test func decodesClawdQuestSprites() throws {
        // Two frames of a 2 × 2 sprite: one pixel changes color.
        let source = ##"var x=1;te={Laptop:{cat:"Core",w:2,h:2,fps:10,palette:"#d97757(#000000".split("("),base:"0.10",deltas:["31"],a0:[0,0,2,2]}},y=2;"##
        let table = try #require(ClawdSprites.spriteTable(in: source))
        let sprite = try #require(table.object("Laptop"))
        let strip = try #require(ClawdSprites.strip(from: sprite))
        #expect(strip.frames.count == 2)
        #expect(strip.size == CGSize(width: 2, height: 2))
        #expect(strip.durations.first == .milliseconds(100))
        #expect(strip.anchor == CGPoint(x: 1, y: 2))
        #expect(strip.body == CGSize(width: 2, height: 2))
        #expect(strip.reach == 0)
    }

    @Test func measuresHowFarAnAnimationReachesAboveTheBody() throws {
        // A 2 × 3 canvas with the body in the bottom two rows; the second frame lights a pixel above it.
        let source = ##"t={Hop:{cat:"Core",w:2,h:3,fps:4,palette:["#ffffff"],base:"..0.00",deltas:["00"],a0:[0,1,2,2]}}"##
        let sprite = try #require(ClawdSprites.spriteTable(in: source)?.object("Hop"))
        let strip = try #require(ClawdSprites.strip(from: sprite))
        #expect(strip.reach == 1)
        #expect(SpriteStrip.opaqueBounds(of: strip.frames[0]) == CGRect(x: 0, y: 1, width: 2, height: 2))
    }
}
