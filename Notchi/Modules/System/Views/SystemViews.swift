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
                BatteryToastLabel(battery: battery, isLow: false)
            case .lowBattery(let battery):
                BatteryToastLabel(battery: battery, isLow: true)
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
                BatteryToastLevel(battery: battery, isLow: false)
            case .lowBattery(let battery):
                BatteryToastLevel(battery: battery, isLow: true)
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

/// Spacing for the charging and low-battery toasts, laid out like the HUD: what happened left of
/// the notch, the level right of it.
enum BatteryToastMetrics {
    /// Room for "Charging" or the percentage and battery, plus the HUD's insets.
    static let chargingWidth: CGFloat = 78
    /// "Low Battery" is a little longer.
    static let lowWidth: CGFloat = 90
}

/// Left of the notch: "Charging" (or "Low Battery"), pinned to the outer edge.
private struct BatteryToastLabel: View {
    let battery: BatteryState
    let isLow: Bool

    var body: some View {
        Text(isLow ? "Low Battery" : (battery.isCharging ? "Charging" : "Plugged In"))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .hudSlot(.leading)
    }
}

/// Right of the notch: the percentage, then the battery filled to it, pinned to the outer edge.
private struct BatteryToastLevel: View {
    let battery: BatteryState
    let isLow: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("\(battery.percent)%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(BatteryIcon.tint(for: battery))
            BatteryIcon(battery: battery, fillsOnAppear: true)
        }
        .hudSlot(.trailing)
    }
}

/// A battery drawn to its real level: an outline with its terminal, filled green while plugged in,
/// red at 20% and below on battery, white otherwise, with a bolt while charging.
struct BatteryIcon: View {
    let battery: BatteryState
    /// Fills up from empty when it appears, like the iPhone's charging animation.
    var fillsOnAppear = false
    @State private var shownLevel: Double?

    private static let size = CGSize(width: 25, height: 12)
    private static let inset: CGFloat = 2

    static func tint(for battery: BatteryState) -> Color {
        if battery.isPluggedIn { return .green }
        return battery.percent <= 20 ? .red : Theme.primary
    }

    var body: some View {
        let level = min(max(shownLevel ?? battery.level, 0), 1)
        let inner = Self.size.width - 2 * Self.inset
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.tertiary, lineWidth: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.tint(for: battery))
                    // A sliver stays visible even near empty, so the color still reads.
                    .frame(width: max(inner * level, level > 0 ? 2.5 : 0))
                    .padding(Self.inset)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .overlay {
                if battery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(Theme.primary)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                }
            }
            UnevenRoundedRectangle(bottomTrailingRadius: 1.5, topTrailingRadius: 1.5)
                .fill(Theme.tertiary)
                .frame(width: 1.5, height: 4)
        }
        .onAppear {
            guard fillsOnAppear else { return }
            shownLevel = 0
            withAnimation(.spring(response: 0.7, dampingFraction: 0.9).delay(0.15)) { shownLevel = nil }
        }
        .accessibilityLabel("Battery \(battery.percent)%")
    }
}

enum VolumeSymbol {
    static func name(level: Double, isMuted: Bool) -> String {
        isMuted || level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }
}

// MARK: - Expanded

/// Battery status, volume and brightness sliders, and the HUD permission prompt.
struct SystemExpandedView: View {
    let module: SystemModule

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let battery = module.battery {
                    StatusTile(
                        icon: AnyView(BatteryIcon(battery: battery)),
                        title: "\(battery.percent)%",
                        subtitle: Self.batterySubtitle(battery)
                    )
                }
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

    private var permissionPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.yellow)
            Text("Allow Accessibility to replace the volume and brightness HUD.")
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

/// A battery toast laid out like in the notch: the label left of the notch, the level right of it.
private struct BatteryPreviewRow: View {
    let battery: BatteryState
    let isLow: Bool

    var body: some View {
        HStack(spacing: 0) {
            BatteryToastLabel(battery: battery, isLow: isLow)
                .frame(width: BatteryToastMetrics.lowWidth)
            Color.clear.frame(width: 120)
            BatteryToastLevel(battery: battery, isLow: isLow)
                .frame(width: BatteryToastMetrics.lowWidth)
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
        BatteryPreviewRow(battery: BatteryState(level: 0.76, isPluggedIn: true, isCharging: true), isLow: false)
        BatteryPreviewRow(battery: BatteryState(level: 0.1, isPluggedIn: false, isCharging: false), isLow: true)
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
