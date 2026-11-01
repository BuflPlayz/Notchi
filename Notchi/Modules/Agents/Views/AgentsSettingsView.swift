import SwiftUI

/// Settings › Agents.
struct AgentsSettingsView: View {
    let module: AgentsModule

    @AppStorage(Preferences.Key.agentAnnouncesDone) private var announcesDone = true
    @AppStorage(Preferences.Key.agentShowsStep) private var showsStep = false
    @AppStorage(Preferences.Key.agentTintsGlass) private var tintsGlass = true
    @Environment(\.moduleRegistry) private var registry

    /// Off stops everything: no folders watched, and installed hooks drop their events.
    private var isEnabled: Bool { registry?.modules.contains { $0.id == module.id } ?? true }

    var body: some View {
        if registry != nil {
            Section {
                ModuleEnabledToggle(moduleID: module.id, title: "Show coding agents in the notch")
            } footer: {
                if !isEnabled {
                    SettingsFootnote("Agents are off: Notchi doesn't watch the agents' files, and hooks you've installed hand nothing over until you turn this back on.")
                }
            }
        }

        Section {
            Toggle("Tint the glass in the agent's color", isOn: $tintsGlass)
            Toggle("Show the current step under the notch", isOn: $showsStep)
            Toggle("Announce finished requests", isOn: $announcesDone)
            LabeledContent("Right now", value: status)
        } header: {
            Text("Coding Agents")
        } footer: {
            SettingsFootnote("Each running session of Claude Code, Codex or Gemini CLI gets its own live activity, with the agent's mascot. One that needs your permission or an answer takes the middle of the notch.")
        }
        .disabled(!isEnabled)

        Section {
            ForEach(AgentKind.allCases) { kind in
                AgentSettingsRow(module: module, kind: kind)
            }
            if let error = module.hookError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Agents")
        } footer: {
            SettingsFootnote("Notchi reads the agents' own session files, so this works without setup. Turn on Hooks for exact, instant steps: Notchi adds a hook to the agent's settings (~/.claude/settings.json, ~/.codex/hooks.json or ~/.gemini/settings.json, keeping a .notchi-backup copy) that hands each step to Notchi and changes nothing else. Codex may ask you to trust the new hook the next time it starts.")
        }
        .task {
            for kind in AgentKind.allCases { module.mascots.load(kind) }
        }
    }

    private var status: String {
        let running = module.runningCount
        return running == 0 ? "No agents running" : running == 1 ? "1 agent running" : "\(running) agents running"
    }
}

private struct AgentSettingsRow: View {
    let module: AgentsModule
    let kind: AgentKind

    var body: some View {
        let present = module.presentAgents.contains(kind)
        LabeledContent {
            Toggle("Hooks", isOn: Binding(
                get: { module.hooked.contains(kind) },
                set: { module.setHooks($0, for: kind) }
            ))
            .disabled(!present && !module.hooked.contains(kind))
        } label: {
            HStack(spacing: 10) {
                AgentMascotView(kind: kind, pose: .idle, height: 20)
                    .frame(width: 32, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.black))
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.name)
                    Text(present ? mascotSource : "Not found on this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var mascotSource: String {
        switch module.mascots.source(for: kind) {
        case .loading: "Loading mascot…"
        case .sprites(let name, let app): "\(name), from \(app)"
        case .appIcon(let app): "\(app) icon"
        case .symbol: kind == .gemini ? "No app to take a mascot from" : "Install its app for the mascot"
        }
    }
}

#Preview("Agents settings") {
    SettingsPane { AgentsSettingsView(module: AgentsModule()) }
        .frame(width: 500)
}
