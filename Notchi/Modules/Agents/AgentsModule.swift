import AppKit
import SwiftUI

/// Coding agents at work: Claude Code, Codex and Gemini CLI, each with its own mascot.
///
/// Every running session is a live activity of its own (`AgentSessionActivity`): the first takes the
/// notch, the next ones become bubbles beside it, and any can be swapped into the middle. Compact
/// mode shows the mascot acting out what the agent does, the time the request has run, and below
/// the notch the current step and the plan's progress. A session waiting for permission or an
/// answer is `urgent` and takes the middle; a finished request is announced with a short toast.
///
/// Sessions are found with no setup by watching the agents' own session files (`AgentLogReader`).
/// Settings › Agents can add Notchi's hook to each agent for exact, instant steps.
@MainActor
@Observable
final class AgentsModule: NotchActivityGroup {
    let id = "agents"
    let title = "Agents"
    let symbol = "sparkles"
    /// The group never shows itself; its sessions do.
    let liveActivity: LiveActivity? = nil

    /// Sessions in the order they were found, which breaks ties between them.
    private(set) var sessions: [AgentSessionActivity] = []
    /// Agents with Notchi's hook installed.
    private(set) var hooked: Set<AgentKind> = []
    private(set) var hookError: String?

    var activities: [any NotchModule] { sessions }

    let mascots = AgentMascots.shared
    @ObservationIgnored let installer: AgentHookInstaller
    @ObservationIgnored private let reader: AgentLogReader
    @ObservationIgnored private let paths: AgentPaths
    @ObservationIgnored private let toastDuration: Duration
    @ObservationIgnored private var fileEvents: FileEventStream?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var sweepTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesObserver: NSObjectProtocol?
    @ObservationIgnored private var isActive = false

    /// Idle sessions stay listed in the panel this long after their last request.
    static let recentWindow: TimeInterval = 30 * 60

    init(paths: AgentPaths = .standard, toastDuration: Duration = .seconds(4)) {
        self.paths = paths
        self.toastDuration = toastDuration
        installer = AgentHookInstaller(paths: paths)
        reader = AgentLogReader(paths: paths)
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        try? installer.writeScript()
        installer.setRunning(true)
        refreshHooks()

        let (stream, continuation) = AsyncStream<[String]>.makeStream()
        let events = FileEventStream(paths: paths.watched.map(\.path)) { continuation.yield($0) }
        events.start()
        fileEvents = events
        let reader = reader
        readTask = Task { [weak self] in
            let found = await reader.scan()
            self?.apply(found, live: false)
            // One reader, in order: a request's end never overtakes its start.
            for await batch in stream {
                let updates = await reader.changed(batch)
                guard !Task.isCancelled else { return }
                self?.apply(updates)
            }
        }
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessions.forEach { $0.refreshActivity() } }
        }
    }

    func stop() {
        isActive = false
        fileEvents?.stop()
        fileEvents = nil
        readTask?.cancel()
        sweepTask?.cancel()
        sweepTask = nil
        installer.setRunning(false)
        sessions.removeAll()
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
        preferencesObserver = nil
    }

    // MARK: Sessions

    /// Running sessions first, then recent idle ones, for the panel.
    var listedSessions: [AgentSessionActivity] {
        let cutoff = Date().addingTimeInterval(-Self.recentWindow)
        let shown = sessions.filter { $0.session.isRunning || $0.isToasting || $0.session.updatedAt > cutoff }
        return shown.filter { $0.session.isRunning } + shown.filter { !$0.session.isRunning }
    }

    var runningCount: Int { sessions.count(where: { $0.session.isRunning }) }

    /// Applies what the sources found. `live` is false for the catch-up at launch, which announces nothing.
    func apply(_ updates: [AgentUpdate], live: Bool = true) {
        let now = Date()
        for update in updates {
            mascots.load(update.kind)
            let activity = session(for: update)
            let wasRunning = activity.session.isRunning
            activity.session.apply(update.event, at: update.date)
            // Only fresh endings are news; a log read late, or replayed, isn't.
            if case .turnEnded(let outcome) = update.event, outcome != .interrupted, wasRunning, live,
               now.timeIntervalSince(update.date) < 20, Preferences.agentAnnouncesDone {
                activity.announceFinish(for: toastDuration)
            }
            if update.event == .ended { scheduleRemoval(of: activity) }
            activity.refreshActivity()
        }
        prune(now: now)
        scheduleSweep()
    }

    private func session(for update: AgentUpdate) -> AgentSessionActivity {
        let id = AgentSession.id(kind: update.kind, sessionID: update.sessionID)
        if let existing = sessions.first(where: { $0.id == id }) { return existing }
        let activity = AgentSessionActivity(
            session: AgentSession(kind: update.kind, sessionID: update.sessionID, at: update.date),
            group: self
        )
        sessions.append(activity)
        return activity
    }

    /// A session that ended leaves after a moment, once the notch has animated its content away.
    private func scheduleRemoval(of activity: AgentSessionActivity) {
        Task { [weak self, weak activity] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, let activity, !activity.session.isRunning, !activity.isToasting else { return }
            self.sessions.removeAll { $0 === activity }
        }
    }

    /// Forgets idle sessions nobody has used in a while. Claude Code's are kept while their process
    /// lives (its status file says when it's gone).
    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.recentWindow * 2)
        sessions.removeAll { activity in
            activity.session.kind != .claude && !activity.session.isRunning && !activity.isToasting
                && activity.session.updatedAt < cutoff
        }
    }

    /// While anything runs, checks every minute that its agent is still alive.
    private func scheduleSweep() {
        guard sweepTask == nil, sessions.contains(where: { $0.session.isRunning }) else { return }
        let reader = reader
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                let updates = await reader.sweep()
                guard let self, !Task.isCancelled else { return }
                self.apply(updates)
                if !self.sessions.contains(where: { $0.session.isRunning }) { break }
            }
            self?.sweepTask = nil
        }
    }

    // MARK: Hooks

    /// The agents that have been run on this Mac.
    var presentAgents: [AgentKind] {
        AgentKind.allCases.filter(installer.isAgentPresent)
    }

    func setHooks(_ enabled: Bool, for kind: AgentKind) {
        do {
            if enabled { try installer.install(kind) } else { try installer.uninstall(kind) }
            hookError = nil
        } catch {
            hookError = error.localizedDescription
        }
        refreshHooks()
    }

    private func refreshHooks() {
        hooked = Set(AgentKind.allCases.filter(installer.isInstalled))
        let passive = Set(AgentKind.allCases).subtracting(hooked)
        let reader = reader
        Task { await reader.setPassive(passive) }
    }

    // MARK: NotchModule views

    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(AgentsExpandedView(module: self)) }
    func settingsView() -> AnyView? { AnyView(AgentsSettingsView(module: self)) }

    #if DEBUG
    /// Fakes a session for the debug commands: `agent:claude:working`, `agent:codex:waiting`,
    /// `agent:gemini:done`, `agent:claude:plan`, `agent:clear` (removes only these fakes).
    func showDebugAgent(_ command: String) {
        if command == "clear" {
            sessions.removeAll { $0.session.sessionID.hasPrefix("debug-") }
            return
        }
        let parts = command.split(separator: ":").map(String.init)
        guard let kind = parts.first.flatMap(AgentKind.init(rawValue:)) else { return }
        let id = "debug-\(kind.rawValue)"
        let now = Date()
        let events: [AgentEvent] = switch parts.dropFirst().first ?? "working" {
        case "thinking": [.seen(title: "Notchi", cwd: nil), .turnStarted]
        case "waiting": [.seen(title: "Notchi", cwd: nil), .turnStarted, .needsInput("Approve: Running xcodebuild")]
        case "done": [.seen(title: "Notchi", cwd: nil), .turnStarted, .turnEnded(.success)]
        case "failed": [.seen(title: "Notchi", cwd: nil), .turnStarted, .turnEnded(.failure)]
        case "plan": [
            .seen(title: "Notchi", cwd: nil), .turnStarted,
            .planUpdated(AgentPlan(items: [
                .init(title: "Study the registry", status: .done),
                .init(title: "Build agent detection", status: .done),
                .init(title: "Drawing the mascots", status: .active),
                .init(title: "Write tests", status: .pending),
            ])),
            .toolStarted(AgentStep(symbol: "pencil", text: "Editing AgentMascots.swift")),
        ]
        default: [.seen(title: "Notchi", cwd: nil), .turnStarted, .toolStarted(AgentStep(symbol: "terminal", text: "Running xcodebuild"))]
        }
        // Started a minute ago, so the timer has something to show.
        apply(events.map { AgentUpdate(kind: kind, sessionID: id, date: $0 == .turnStarted ? now.addingTimeInterval(-64) : now, event: $0) })
    }
    #endif
}

/// One agent session as a live activity of its own.
@MainActor
@Observable
final class AgentSessionActivity: NotchModule {
    let id: String
    var session: AgentSession
    /// True for a few seconds after a request ends, while compact mode says so.
    private(set) var isToasting = false
    private(set) var liveActivity: LiveActivity?

    @ObservationIgnored weak var group: AgentsModule?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(session: AgentSession, group: AgentsModule?) {
        id = session.id
        self.session = session
        self.group = group
    }

    var title: String { "\(session.kind.name) · \(session.title)" }
    var symbol: String { "sparkles" }
    /// Shown on the Agents page, not a page of its own.
    var showsInPanel: Bool { false }

    func announceFinish(for duration: Duration) {
        isToasting = true
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            self.isToasting = false
            self.refreshActivity()
        }
    }

    /// Recomputes the live activity from the session and the settings.
    func refreshActivity() {
        let tint = Preferences.agentTintsGlass ? session.kind.tint : nil
        let activity: LiveActivity?
        if isToasting {
            activity = LiveActivity(priority: .transient, sideWidth: max(Preferences.compactSideWidth, AgentMetrics.sideWidth), surfaceTint: tint)
        } else {
            let priority: LiveActivity.Priority? = switch session.phase {
            case .needsInput: .urgent
            case .thinking, .working: .active
            case .idle, .finished: nil
            }
            activity = priority.map {
                LiveActivity(
                    priority: $0,
                    sideWidth: max(Preferences.compactSideWidth, AgentMetrics.sideWidth),
                    belowHeight: Preferences.agentShowsStep ? AgentMetrics.stepRowHeight : 0,
                    surfaceTint: tint
                )
            }
        }
        if activity != liveActivity { liveActivity = activity }
    }

    func compactLeading() -> AnyView { AnyView(AgentCompactLeading(activity: self)) }
    func compactTrailing() -> AnyView { AnyView(AgentCompactTrailing(activity: self)) }
    func compactMinimal() -> AnyView { AnyView(AgentBubble(activity: self)) }
    func compactBelow() -> AnyView? { AnyView(AgentStepRow(activity: self)) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}
