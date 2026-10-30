import AppKit

/// Trackpad haptics. Only felt while a finger rests on a Force Touch trackpad; a no-op otherwise.
@MainActor
enum Haptics {
    static func expand() {
        guard Preferences.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
