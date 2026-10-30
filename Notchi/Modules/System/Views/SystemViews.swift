import SwiftUI

// MARK: - Compact (toasts)

/// Spacing for the volume and brightness HUD, which fits in the notch's own row: the icon and the
/// number left of the notch, the level bar right of it. One inset is used for the icon's left edge
/// and the bar's right edge, so the HUD mirrors itself around the notch.
enum HUDMetrics {
    /// Distance from the shape's sides (inside the notch's ears) to the HUD's content.
    static let inset: CGFloat = 12
    /// Distance from the notch to the content beside it: the number's right edge, the bar's left end.
    static let notchGap: CGFloat = 8
    /// Compact slot width the HUD asks for: room for the icon and the number on one side, and a
    /// bar of the same length on the other.
    static let sideWidth: CGFloat = 66
    static let barHeight: CGFloat = 6
}

extension View {
    /// Pins HUD content to the outer edge of its side slot, `HUDMetrics.inset` in, whatever the
    /// compact layout setting.
    func hudSlot(_ edge: HorizontalEdge) -> some View {
        modifier(HUDSlot(edge: edge))
    }
}

private struct HUDSlot: ViewModifier {
    let edge: HorizontalEdge
    @Environment(\.compactAlignment) private var alignment

    func body(content: Content) -> some View {
        // With Edges on, the slot has already pinned it and padded part of the way.
        let padding = HUDMetrics.inset - (alignment == .edges ? Metrics.compactEdgeInset : 0)
        content
            .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
            .padding(edge == .leading ? .leading : .trailing, padding)
    }
}

/// Left slot: the toast's icon, and the HUD's number next to it.
struct SystemCompactLeading: View {
    let module: SystemModule

    var body: some View {
        Group {
            switch module.toast {
            case .volume(let level, let isMuted):
                HUDLeading(icon: VolumeHUDIcon(level: level, isMuted: isMuted), value: level, isMuted: isMuted)
            case .brightness(let level):
                HUDLeading(icon: BrightnessHUDIcon(level: level), value: level, isMuted: false)
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

/// Right slot: the HUD's level bar, or the toast's short status.
struct SystemCompactTrailing: View {
    let module: SystemModule

    var body: some View {
        Group {
            switch module.toast {
            case .volume(let level, let isMuted):
                HUDBar(value: isMuted ? 0 : level)
            case .brightness(let level):
                HUDBar(value: level)
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

/// The HUD's left side: the icon pinned to the outer edge, the number running up to the notch.
private struct HUDLeading<Icon: View>: View {
    let icon: Icon
    let value: Double
    let isMuted: Bool

    var body: some View {
        HStack(spacing: 0) {
            icon
            Spacer(minLength: 4)
            HUDValue(value: value, isMuted: isMuted)
        }
        .padding(.trailing, HUDMetrics.notchGap)
        .hudSlot(.leading)
    }
}

/// The HUD's right side: the level bar from the notch out to the outer edge.
private struct HUDBar: View {
    let value: Double

    var body: some View {
        LevelBar(value: value)
            .padding(.leading, HUDMetrics.notchGap)
            .hudSlot(.trailing)
    }
}

/// The HUD's percentage, whose digits roll as it changes. Animated by the transaction the
/// module updates the toast in (`Motion.hud`).
struct HUDValue: View {
    let value: Double
    let isMuted: Bool

    private var percent: Int { isMuted ? 0 : Int((min(max(value, 0), 1) * 100).rounded()) }

    var body: some View {
        Text("\(percent)")
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(isMuted ? Theme.tertiary : Theme.primary)
            .contentTransition(.numericText(value: Double(percent)))
    }
}

/// A thin capsule showing 0…1, with a soft glow at the leading edge of the fill.
struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.controlFill)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.primary.opacity(0.75), Theme.primary], startPoint: .leading, endPoint: .trailing))
                    .frame(width: clamped > 0 ? max(geometry.size.width * clamped, geometry.size.height) : 0)
                    .shadow(color: Theme.primary.opacity(0.35), radius: 3)
            }
        }
        .frame(height: HUDMetrics.barHeight)
    }
}

/// Speaker whose waves fill with the level; bounces when muting or unmuting.
struct VolumeHUDIcon: View {
    let level: Double
    let isMuted: Bool

    var body: some View {
        Image(systemName: VolumeSymbol.name(level: level, isMuted: isMuted), variableValue: isMuted ? 0 : max(level, 0.001))
            .foregroundStyle(Theme.primary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: isMuted)
            .frame(width: 22, alignment: .leading)
    }
}

/// Sun that grows with brightness (from its leading edge, so the HUD's padding never shifts) and
/// swaps between its small and large form.
struct BrightnessHUDIcon: View {
    let level: Double

    var body: some View {
        Image(systemName: level < 0.5 ? "sun.min.fill" : "sun.max.fill")
            .foregroundStyle(Theme.primary)
            .contentTransition(.symbolEffect(.replace))
            .scaleEffect(0.8 + 0.2 * min(max(level, 0), 1), anchor: .leading)
            .frame(width: 18, alignment: .leading)
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

/// The HUD laid out like in the notch: icon and number left of the notch, bar right of it.
private struct HUDPreviewRow: View {
    let icon: AnyView
    let value: Double
    let isMuted: Bool

    var body: some View {
        HStack(spacing: 0) {
            HUDLeading(icon: icon, value: value, isMuted: isMuted)
                .frame(width: HUDMetrics.sideWidth)
            Color.clear.frame(width: 120)
            HUDBar(value: isMuted ? 0 : value)
                .frame(width: HUDMetrics.sideWidth)
        }
        .frame(height: 32)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview("Compact toasts") {
    VStack(spacing: 12) {
        HUDPreviewRow(icon: AnyView(VolumeHUDIcon(level: 0.6, isMuted: false)), value: 0.6, isMuted: false)
        HUDPreviewRow(icon: AnyView(BrightnessHUDIcon(level: 0.3)), value: 0.3, isMuted: false)
        HUDPreviewRow(icon: AnyView(VolumeHUDIcon(level: 0.6, isMuted: true)), value: 0.6, isMuted: true)
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

#Preview("HUD animation") {
    struct Demo: View {
        @State private var level = 0.3
        var body: some View {
            VStack(spacing: 14) {
                HUDPreviewRow(icon: AnyView(VolumeHUDIcon(level: level, isMuted: false)), value: level, isMuted: false)
                HStack {
                    Button("−") { withAnimation(Motion.hud) { level = LevelStep.next(from: level, up: false, fine: false) } }
                    Button("+") { withAnimation(Motion.hud) { level = LevelStep.next(from: level, up: true, fine: false) } }
                }
            }
            .padding(20)
            .background(Theme.surface)
        }
    }
    return Demo()
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
