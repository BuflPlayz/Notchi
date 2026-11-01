import Foundation

/// What an agent is doing right now, as one line: "Editing NotchShape.swift".
struct AgentStep: Equatable, Sendable {
    /// SF Symbol for the kind of work.
    var symbol: String
    var text: String
}

/// An agent's to-do list for the request, when it keeps one (Claude Code's todos and tasks, Codex's
/// and the Claude app's plan, Gemini's todos). It's the only real measure of progress an agent gives.
struct AgentPlan: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        enum Status: Equatable, Sendable {
            case pending, active, done
        }
        var title: String
        var status: Status
        /// Kept for tools that update items by id (Claude Code's TaskUpdate).
        var key: String? = nil
    }

    var items: [Item]

    var total: Int { items.count }
    var completed: Int { items.count(where: { $0.status == .done }) }
    var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    /// The item being worked on, or else the next one up.
    var current: Item? { items.first { $0.status == .active } ?? items.first { $0.status == .pending } }
    var isFinished: Bool { total > 0 && completed == total }

    /// Maps the status words agents use: pending, in_progress, completed, cancelled…
    static func status(_ word: String?) -> Item.Status {
        switch word?.lowercased() {
        case "in_progress", "in-progress", "active", "running": .active
        case "completed", "complete", "done", "cancelled", "canceled", "skipped": .done
        default: .pending
        }
    }
}

/// How a request ended.
enum AgentOutcome: Equatable, Sendable {
    case success
    case failure
    /// Stopped by the user: no toast.
    case interrupted
}

/// One thing that happened in an agent session, the same whichever agent or source reported it.
enum AgentEvent: Equatable, Sendable {
    /// The session exists (started, or found running). Fills in its name and folder.
    case seen(title: String?, cwd: String?)
    /// The user sent a request.
    case turnStarted
    /// The agent is working without a tool running (thinking, writing its answer).
    case thinking
    case toolStarted(AgentStep)
    case toolFinished
    case planUpdated(AgentPlan)
    /// Advances the plan in place (the Claude app's `update_plan` with `advance`, `done` or `start`).
    case planEdited(AgentPlanEdit)
    /// Waiting on the user: a permission prompt or a question.
    case needsInput(String)
    case turnEnded(AgentOutcome)
    /// The session's process is gone.
    case ended
}

/// A relative change to a plan, for tools that send only what changed.
enum AgentPlanEdit: Equatable, Sendable {
    /// Finish the active item and start the next pending one.
    case advance
    /// Mark items done and start one, by 0-based index.
    case mark(done: [Int], start: Int?)
    /// Set one item's status by key (Claude Code's TaskUpdate). A nil status removes it.
    case setStatus(key: String, status: AgentPlan.Item.Status?)
    /// Append an item (Claude Code's TaskCreate).
    case append(AgentPlan.Item)
}

/// An event for one session, as a source reports it.
struct AgentUpdate: Equatable, Sendable {
    let kind: AgentKind
    let sessionID: String
    let date: Date
    let event: AgentEvent
}

/// The state of one session of a coding agent, built up from its events.
struct AgentSession: Identifiable, Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Waiting for the user's next request.
        case idle
        case thinking
        case working
        case needsInput
        /// The request just ended; `finished` says how.
        case finished
    }

    let kind: AgentKind
    let sessionID: String
    var title: String
    var cwd: String?
    var phase = Phase.idle
    var step: AgentStep?
    /// Why the agent is waiting, while `phase` is `.needsInput`.
    var prompt: String?
    var plan: AgentPlan?
    /// When the current (or last) request started.
    var turnStartedAt: Date?
    /// When the last request ended, and how.
    var finishedAt: Date?
    var outcome: AgentOutcome?
    /// Tools used in the current request.
    var toolCount = 0
    var updatedAt: Date

    var id: String { Self.id(kind: kind, sessionID: sessionID) }

    static func id(kind: AgentKind, sessionID: String) -> String { "agent.\(kind.rawValue).\(sessionID)" }

    init(kind: AgentKind, sessionID: String, title: String? = nil, cwd: String? = nil, at date: Date) {
        self.kind = kind
        self.sessionID = sessionID
        self.cwd = cwd
        self.title = title ?? cwd.map { URL(filePath: $0).lastPathComponent } ?? kind.name
        updatedAt = date
    }

    /// True while a request is in flight (including a pause for the user's answer).
    var isRunning: Bool {
        switch phase {
        case .thinking, .working, .needsInput: true
        case .idle, .finished: false
        }
    }

    mutating func apply(_ event: AgentEvent, at date: Date) {
        updatedAt = max(updatedAt, date)
        switch event {
        case .seen(let newTitle, let newCwd):
            if let newCwd, !newCwd.isEmpty { cwd = newCwd }
            if let newTitle, !newTitle.isEmpty {
                title = newTitle
            } else if title == kind.name, let cwd {
                title = URL(filePath: cwd).lastPathComponent
            }
        case .turnStarted:
            // Reported twice when hooks and logs both see it; the first one counts.
            guard !isRunning else { return }
            turnStartedAt = date
            phase = .thinking
            step = nil
            prompt = nil
            toolCount = 0
            outcome = nil
            // A finished plan belongs to the last request; an open one carries on.
            if plan?.isFinished == true { plan = nil }
        case .thinking:
            beginIfIdle(at: date)
            phase = .thinking
            prompt = nil
        case .toolStarted(let newStep):
            beginIfIdle(at: date)
            phase = .working
            step = newStep
            prompt = nil
            toolCount += 1
        case .toolFinished:
            guard isRunning else { return }
            phase = .thinking
            prompt = nil
        case .planUpdated(let newPlan):
            plan = newPlan.items.isEmpty ? nil : newPlan
        case .planEdited(let edit):
            var edited = plan ?? AgentPlan(items: [])
            edited.apply(edit)
            plan = edited.items.isEmpty ? nil : edited
        case .needsInput(let reason):
            beginIfIdle(at: date)
            phase = .needsInput
            prompt = reason
        case .turnEnded(let how):
            guard isRunning else { return }
            phase = how == .interrupted ? .idle : .finished
            outcome = how
            finishedAt = date
            prompt = nil
        case .ended:
            if isRunning { phase = .idle }
            prompt = nil
        }
    }

    /// Events that only make sense mid-request (a tool) start one if the start wasn't seen.
    private mutating func beginIfIdle(at date: Date) {
        guard !isRunning else { return }
        turnStartedAt = date
        toolCount = 0
        outcome = nil
    }
}

extension AgentPlan {
    mutating func apply(_ edit: AgentPlanEdit) {
        switch edit {
        case .advance:
            if let active = items.firstIndex(where: { $0.status == .active }) {
                items[active].status = .done
            }
            if let next = items.firstIndex(where: { $0.status == .pending }) {
                items[next].status = .active
            }
        case .mark(let done, let start):
            for index in done where items.indices.contains(index) { items[index].status = .done }
            if let start, items.indices.contains(start) {
                for index in items.indices where items[index].status == .active { items[index].status = .pending }
                items[start].status = .active
            }
        case .setStatus(let key, let status):
            guard let index = items.firstIndex(where: { $0.key == key }) else { return }
            if let status { items[index].status = status } else { items.remove(at: index) }
        case .append(var item):
            // Claude Code numbers tasks 1, 2, 3… in the order they're created.
            if item.key == nil { item.key = String((items.compactMap { $0.key.flatMap(Int.init) }.max() ?? 0) + 1) }
            items.append(item)
        }
    }
}
