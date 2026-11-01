import SwiftUI

/// Sizes for agent content in the notch.
enum AgentMetrics {
    /// Each compact slot: the mascot on the left, the time or plan count on the right.
    static let sideWidth: CGFloat = 46
    /// The row under the notch with the current step.
    static let stepRowHeight: CGFloat = 22
    static let compactMascotHeight: CGFloat = 19
}

/// Waiting on the user: the same orange as a timer's last seconds.
private let attentionColor = Color.orange

// MARK: - Compact

/// Left slot: the mascot acting out what the agent does.
struct AgentCompactLeading: View {
    let activity: AgentSessionActivity
    @Environment(\.compactAlignment) private var alignment

    var body: some View {
        // The mascot sits in the middle of the slot, which starts at the top of the screen: what
        // reaches higher than the space above it would go off screen.
        GeometryReader { proxy in
            AgentMascotView(
                kind: activity.session.kind,
                pose: pose,
                height: AgentMetrics.compactMascotHeight,
                headroom: max(0, (proxy.size.height - AgentMetrics.compactMascotHeight) / 2)
            )
            .notchMatchedGeometry(id: "\(activity.id).mascot")
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: alignment == .edges ? .leading : .center)
        }
    }

    /// A toast celebrates (or sulks) whatever the session moved on to.
    private var pose: MascotPose {
        activity.isToasting ? (activity.session.outcome == .failure ? .failed : .celebrating) : activity.session.pose
    }
}

/// Right slot: "Done" after a request, a hand while the agent waits for the user, the plan's count
/// while it has one, or else how long the request has run.
struct AgentCompactTrailing: View {
    let activity: AgentSessionActivity

    var body: some View {
        let session = activity.session
        Group {
            if activity.isToasting {
                Text(session.outcome == .failure ? "Failed" : "Done")
                    .foregroundStyle(session.outcome == .failure ? attentionColor : session.kind.tint)
            } else if session.phase == .needsInput {
                LayerSymbol(name: "hand.raised.fill", style: AnyShapeStyle(attentionColor), styleKey: "attention", size: 14, pulses: true)
            } else if let plan = session.plan {
                Text("\(plan.completed)/\(plan.total)")
                    .foregroundStyle(session.kind.tint)
                    .contentTransition(.numericText())
            } else {
                AgentElapsedText(session: session)
                    .foregroundStyle(session.kind.tint)
            }
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// The round bubble beside the notch: the mascot, with an orange dot while it needs the user.
struct AgentBubble: View {
    let activity: AgentSessionActivity

    var body: some View {
        // Inside a round bubble that clips: only what fits around the body.
        AgentMascotView(kind: activity.session.kind, pose: activity.session.pose, height: 16, headroom: 4)
            .overlay(alignment: .topTrailing) {
                if activity.session.phase == .needsInput {
                    Circle()
                        .fill(attentionColor)
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: -2)
                }
            }
    }
}

/// Under the notch: what the agent is doing right now, and the plan's progress.
struct AgentStepRow: View {
    let activity: AgentSessionActivity

    var body: some View {
        let session = activity.session
        HStack(spacing: 6) {
            Image(systemName: symbol(for: session))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(session.phase == .needsInput ? attentionColor : session.kind.tint)
                .frame(width: 12)
            Text(stepText(for: session))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(session.phase == .needsInput ? attentionColor : Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
                .animation(Motion.content, value: stepText(for: session))
            Spacer(minLength: 4)
            if let plan = session.plan {
                AgentPlanBar(plan: plan, tint: session.kind.tint)
                    .frame(width: 36, height: 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func symbol(for session: AgentSession) -> String {
        switch session.phase {
        case .needsInput: "hand.raised.fill"
        case .working: session.step?.symbol ?? "ellipsis"
        default: "ellipsis"
        }
    }

    private func stepText(for session: AgentSession) -> String {
        switch session.phase {
        case .needsInput: session.prompt ?? "Needs your input"
        case .working: session.step?.text ?? "Working"
        default: session.plan?.current?.title ?? "Thinking…"
        }
    }
}

// MARK: - Building blocks

/// The request's running time, redrawn by SwiftUI itself (no timer of ours).
struct AgentElapsedText: View {
    let session: AgentSession

    var body: some View {
        if session.isRunning, let start = session.turnStartedAt {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
        } else if let start = session.turnStartedAt, let end = session.finishedAt, end >= start {
            Text(AgentFormat.duration(end.timeIntervalSince(start)))
        } else {
            Text("–")
        }
    }
}

/// A thin capsule filled to the plan's progress.
struct AgentPlanBar: View {
    let plan: AgentPlan
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.controlFill)
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.height, proxy.size.width * plan.fraction))
                    .animation(Motion.content, value: plan.fraction)
            }
        }
    }
}

enum AgentFormat {
    /// "42s", "3m 05s", "1h 02m".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return String(format: "%dm %02ds", total / 60, total % 60) }
        return String(format: "%dh %02dm", total / 3600, total % 3600 / 60)
    }

    /// "Working", "Needs you", "Done in 3m 05s", "Idle".
    static func status(of session: AgentSession) -> String {
        switch session.phase {
        case .thinking: return "Thinking"
        case .working: return session.toolCount > 1 ? "Working · step \(session.toolCount)" : "Working"
        case .needsInput: return "Needs you"
        case .finished, .idle:
            guard let start = session.turnStartedAt, let end = session.finishedAt, end >= start else { return "Idle" }
            let verb = session.outcome == .failure ? "Failed after" : "Done in"
            return "\(verb) \(duration(end.timeIntervalSince(start)))"
        }
    }
}

// MARK: - Expanded

/// The Agents page: every running session, then recent idle ones.
struct AgentsExpandedView: View {
    let module: AgentsModule

    var body: some View {
        let sessions = module.listedSessions
        if sessions.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    ForEach(sessions, id: \.id) { activity in
                        AgentSessionRow(activity: activity)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 16) {
            HStack(spacing: -6) {
                ForEach(AgentKind.allCases) { kind in
                    AgentMascotView(kind: kind, pose: .idle, height: 22)
                }
            }
            .frame(width: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text("No agents running").font(Theme.title)
                Text("Start Claude Code, Codex or Gemini CLI, and each request shows up here as it runs.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

/// One session: mascot, project, what it's doing, the plan's progress and the time.
private struct AgentSessionRow: View {
    let activity: AgentSessionActivity

    var body: some View {
        let session = activity.session
        HStack(alignment: .center, spacing: 10) {
            // Props stick out to the right (Clawd's desktop, a laptop): the column leaves them room.
            AgentMascotView(kind: session.kind, pose: activity.isToasting ? .celebrating : session.pose, height: 24, headroom: 8)
                .notchMatchedGeometry(id: "\(activity.id).mascot")
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(Theme.body.weight(.semibold))
                        .lineLimit(1)
                    Text(session.kind.name)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
                Text(detail(for: session))
                    .font(Theme.caption)
                    .foregroundStyle(session.phase == .needsInput ? attentionColor : Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let plan = session.plan {
                    HStack(spacing: 6) {
                        AgentPlanBar(plan: plan, tint: session.kind.tint)
                            .frame(height: 3)
                        Text("\(plan.completed) of \(plan.total)")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize()
                    }
                }
            }
            Spacer(minLength: 6)
            AgentElapsedText(session: session)
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(session.isRunning ? session.kind.tint : Theme.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.controlFill.opacity(session.isRunning ? 1 : 0.4)))
        .opacity(session.isRunning || activity.isToasting ? 1 : 0.7)
        .help(session.cwd ?? session.title)
    }

    /// The step, the question, or how the last request went.
    private func detail(for session: AgentSession) -> String {
        switch session.phase {
        case .needsInput: session.prompt ?? "Needs your input"
        case .working: session.step?.text ?? "Working"
        case .thinking: session.plan?.current.map { "Thinking · \($0.title)" } ?? "Thinking…"
        case .finished, .idle: AgentFormat.status(of: session)
        }
    }
}

// MARK: - Previews

#Preview("Agents page") {
    let module = AgentsModule()
    #if DEBUG
    module.showDebugAgent("claude:plan")
    module.showDebugAgent("codex:waiting")
    module.showDebugAgent("gemini:working")
    #endif
    return AgentsExpandedView(module: module)
        .frame(width: 408, height: 140)
        .padding()
        .background(Theme.surface)
        .foregroundStyle(Theme.primary)
}
