import Foundation
import Observation
import os

/// Owns the system audio tap and publishes band levels to the UI.
///
/// Runs only while music plays. Before audio has ever arrived (permission pending or denied),
/// `displayLevels` is nil and the visualizer falls back to its synthetic animation. Once real audio
/// has been seen, silence shows as resting bars instead.
@MainActor
@Observable
final class AudioLevelMonitor {
    let bandCount: Int
    private(set) var levels: [Double] = []
    private(set) var isRunning = false

    @ObservationIgnored private var tap: AnyObject?
    @ObservationIgnored private var lastSignal = Date.distantPast
    @ObservationIgnored private var hasEverHadSignal = false
    @ObservationIgnored private let logger = Logger(subsystem: "dev.notchi.Notchi", category: "AudioTap")

    init(bandCount: Int = 4) {
        self.bandCount = bandCount
    }

    /// Levels for the visualizer: real while audio flows, resting during silence, or nil to use
    /// the synthetic animation when no audio has ever arrived.
    var displayLevels: [Double]? {
        guard isRunning, hasEverHadSignal else { return nil }
        if Date().timeIntervalSince(lastSignal) > 1.5 { return Array(repeating: 0.12, count: bandCount) }
        return levels
    }

    func start() {
        guard !isRunning else { return }
        guard #available(macOS 14.2, *) else { return }
        let tap = SystemAudioTap()
        do {
            try tap.start(bandCount: bandCount) { [weak self] levels in
                Task { @MainActor in self?.receive(levels) }
            }
            self.tap = tap
            isRunning = true
        } catch {
            logger.error("Audio tap unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        guard isRunning else { return }
        if #available(macOS 14.2, *) { (tap as? SystemAudioTap)?.stop() }
        tap = nil
        isRunning = false
        levels = []
    }

    private func receive(_ newLevels: [Float]) {
        guard isRunning else { return }
        if newLevels.contains(where: { $0 > 0.02 }) {
            lastSignal = Date()
            hasEverHadSignal = true
        }
        levels = newLevels.map(Double.init)
    }
}
