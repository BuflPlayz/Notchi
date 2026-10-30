import SwiftUI

// MARK: - Compact (toasts)

/// Left slot: the toast's icon.
struct SystemCompactLeading: View {
    let module: SystemModule

    var body: some View {
        Group {
            switch module.toast {
            case .volume(let level, let isMuted):
                Image(systemName: VolumeSymbol.name(level: level, isMuted: isMuted), variableValue: isMuted ? 0 : level)
                    .foregroundStyle(Theme.primary)
                    .contentTransition(.symbolEffect(.replace))
            case .brightness(let level):
                Image(systemName: level < 0.5 ? "sun.min.fill" : "sun.max.fill")
                    .foregroundStyle(Theme.primary)
                    .contentTransition(.symbolEffect(.replace))
            case .charging(let battery):
                BatteryGlyph(battery: battery)
            case .lowBattery(let battery):
                BatteryGlyph(battery: battery)
            case .focus(let focus):
                Image(systemName: focus.isActive ? "moon.fill" : "moon")
                    .foregroundStyle(focus.isActive ? Color.indigo : Theme.secondary)
            case nil:
                EmptyView()
            }
        }
        .font(.system(size: 14, weight: .semibold))
    }
}

/// Right slot: a level bar for the HUD, or the toast's short status.
struct SystemCompactTrailing: View {
    let module: SystemModule

    var body: some View {
        Group {
            switch module.toast {
            case .volume(let level, let isMuted):
                LevelBar(value: isMuted ? 0 : level)
            case .brightness(let level):
                LevelBar(value: level)
            case .charging(let battery):
                Text("\(battery.percent)%").foregroundStyle(.green)
            case .lowBattery(let battery):
                Text("\(battery.percent)%").foregroundStyle(.red)
            case .focus(let focus):
                Text(focus.isActive ? "On" : "Off").foregroundStyle(focus.isActive ? Color.indigo : Theme.secondary)
            case nil:
                EmptyView()
            }
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .lineLimit(1)
    }
}

/// A thin capsule showing 0…1, for the compact HUD.
struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.controlFill)
                Capsule()
                    .fill(Theme.primary)
                    .frame(width: max(geometry.size.width * min(max(value, 0), 1), value > 0 ? 4 : 0))
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 4)
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: value)
    }
}

/// Battery symbol for a level, with a bolt while plugged in. Red at 20% and below on battery.
struct BatteryGlyph: View {
    let battery: BatteryState

    var body: some View {
        Image(systemName: Self.symbol(for: battery))
            .symbolRenderingMode(.palette)
            .foregroundStyle(color, Theme.primary)
    }

    private var color: Color {
        if battery.isPluggedIn { return .green }
        return battery.percent <= 20 ? .red : Theme.primary
    }

    static func symbol(for battery: BatteryState) -> String {
        if battery.isPluggedIn { return "battery.100percent.bolt" }
        switch battery.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

enum VolumeSymbol {
    static func name(level: Double, isMuted: Bool) -> String {
        isMuted || level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }
}

// MARK: - Expanded

/// Battery and Focus status, volume and brightness sliders, and the HUD permission prompt.
struct SystemExpandedView: View {
    let module: SystemModule

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let battery = module.battery {
                    StatusTile(
                        icon: AnyView(BatteryGlyph(battery: battery)),
                        title: "\(battery.percent)%",
                        subtitle: Self.batterySubtitle(battery)
                    )
                }
                StatusTile(
                    icon: AnyView(Image(systemName: module.focus.isActive ? "moon.fill" : "moon")
                        .foregroundStyle(module.focus.isActive ? Color.indigo : Theme.secondary)),
                    title: module.focus.isActive ? (module.focus.name ?? "Focus") : "Focus",
                    subtitle: focusSubtitle
                )
            }

            HStack(spacing: 16) {
                NotchSlider(
                    value: module.volume.effectiveLevel,
                    symbol: VolumeSymbol.name(level: module.volume.level, isMuted: module.volume.isMuted),
                    isEnabled: module.volume.canChange,
                    onSymbolTap: module.toggleMute,
                    onChange: module.setVolume
                )
                NotchSlider(
                    value: module.brightness ?? 0,
                    symbol: "sun.max.fill",
                    isEnabled: module.brightness != nil,
                    onChange: module.setBrightness
                )
            }

            if !module.permission.isGranted && Preferences.replaceSystemHUD {
                permissionPrompt
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear(perform: module.refreshBrightness)
    }

    private var focusSubtitle: String {
        if !module.permission.isGranted { return "Needs Accessibility" }
        return module.focus.isActive ? "On" : "Off"
    }

    private var permissionPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.yellow)
            Text("Allow Accessibility to replace the volume and brightness HUD and show Focus.")
                .font(Theme.caption)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Allow…", action: module.requestAccessibility)
                .buttonStyle(NotchButtonStyle())
        }
    }

    static func batterySubtitle(_ battery: BatteryState) -> String {
        let time = battery.minutesRemaining.map { minutes in
            minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        }
        if battery.isCharged || (battery.isPluggedIn && battery.percent >= 100) { return "Charged" }
        if battery.isCharging { return time.map { "Charging · \($0) to full" } ?? "Charging" }
        if battery.isPluggedIn { return "Plugged in, not charging" }
        return time.map { "\($0) left" } ?? "On battery"
    }
}

/// A rounded tile with an icon, a value and a caption.
private struct StatusTile: View {
    let icon: AnyView
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            icon
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.body.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.controlFill))
    }
}

/// A Control Center-style slider: a thick capsule that fills from the left, with its icon inside.
struct NotchSlider: View {
    let value: Double
    let symbol: String
    var isEnabled = true
    var onSymbolTap: (() -> Void)?
    let onChange: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geometry in
            let shown = dragValue ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.controlFill)
                Capsule()
                    .fill(Theme.primary.opacity(0.9))
                    .frame(width: max(geometry.size.height, geometry.size.width * shown))
                    .opacity(shown > 0 ? 1 : 0)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(shown > 0.12 ? Color.black : Theme.secondary)
                    .frame(width: geometry.size.height, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { onSymbolTap?() }
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = min(max(drag.location.x / geometry.size.width, 0), 1)
                        dragValue = fraction
                        onChange(fraction)
                    }
                    .onEnded { _ in dragValue = nil }
            )
        }
        .frame(height: 22)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: dragValue == nil ? value : nil)
    }
}

// MARK: - Previews

#Preview("Compact toasts") {
    VStack(spacing: 12) {
        HStack(spacing: 20) {
            Image(systemName: "speaker.wave.3.fill", variableValue: 0.6).foregroundStyle(.white)
            LevelBar(value: 0.6).frame(width: 56)
        }
        HStack(spacing: 20) {
            BatteryGlyph(battery: BatteryState(level: 0.76, isPluggedIn: true, isCharging: true))
            Text("76%").foregroundStyle(.green)
        }
        HStack(spacing: 20) {
            BatteryGlyph(battery: BatteryState(level: 0.1, isPluggedIn: false, isCharging: false))
            Text("10%").foregroundStyle(.red)
        }
    }
    .font(.system(size: 14, weight: .semibold))
    .padding(20)
    .background(Theme.surface)
}

#Preview("Sliders") {
    VStack(spacing: 12) {
        NotchSlider(value: 0.6, symbol: "speaker.wave.3.fill") { _ in }
        NotchSlider(value: 0.05, symbol: "sun.max.fill") { _ in }
        NotchSlider(value: 0.4, symbol: "sun.max.fill", isEnabled: false) { _ in }
    }
    .frame(width: 200)
    .padding(20)
    .background(Theme.surface)
}
