import Foundation
import Testing
@testable import Notchi

struct ClockSnapshotTests {
    /// Shapes copied from a real `com.apple.mobiletimerd` domain on macOS 27.2.
    private func timer(id: String, state: Int, fire: [String: Any], title: String = "", duration: Double = 3000) -> [String: Any] {
        ["$MTTimer": [
            "MTTimerID": id, "MTTimerState": state, "MTTimerDuration": duration,
            "MTTimerFireTime": fire, "MTTimerTitle": title,
        ] as [String: Any]]
    }

    @Test func decodesRunningPausedAndStoppedTimers() throws {
        let fireDate = Date(timeIntervalSince1970: 2_000_000_000)
        let timers: [String: Any] = ["MTTimers": [
            timer(id: "stopped", state: 1, fire: ["$MTTimerTimeInterval": ["MTTimerTimeInterval": 900]], title: "CURRENT_TIMER"),
            timer(id: "paused", state: 2, fire: ["$MTTimerTimeInterval": ["MTTimerTimeInterval": "2680.69749712944"]]),
            timer(id: "running", state: 3, fire: ["$MTTimerDate": ["MTTimerTimeDate": fireDate]], title: "Tea"),
        ]]
        let snapshot = ClockSnapshot(timersValue: timers, stopwatchesValue: nil)

        #expect(snapshot.timers.map(\.id) == ["paused", "running"])        // stopped timers are hidden
        let paused = try #require(snapshot.timers.first { $0.id == "paused" })
        #expect(paused.state == .paused(remaining: 2680.69749712944))      // string-encoded number
        #expect(paused.title == nil)
        let running = try #require(snapshot.timers.first { $0.id == "running" })
        #expect(running.state == .running(fireDate: fireDate))
        #expect(running.title == "Tea")
        #expect(snapshot.primaryTimer?.id == "running")                    // running beats paused
    }

    @Test func decodesStopwatch() {
        let start = Date(timeIntervalSince1970: 1_000)
        func stopwatches(state: Int, offset: Double, start: Date?) -> [String: Any] {
            var entry: [String: Any] = ["MTStopwatchIdentifier": "sw", "MTStopwatchState": state, "MTStopwatchOffset": offset, "MTStopwatchLaps": [1, 2]]
            entry["MTStopwatchStartDate"] = start
            return ["MTStopwatches": [["$MTStopwatch": entry]]]
        }

        let running = ClockSnapshot(timersValue: nil, stopwatchesValue: stopwatches(state: 2, offset: 283.37, start: start)).stopwatch
        #expect(running?.state == .running(since: start, offset: 283.37))
        #expect(running?.elapsed(at: start.addingTimeInterval(10)) == 293.37)
        #expect(running?.virtualStart == start.addingTimeInterval(-283.37))
        #expect(running?.lapCount == 2)

        let paused = ClockSnapshot(timersValue: nil, stopwatchesValue: stopwatches(state: 1, offset: 283.37, start: nil)).stopwatch
        #expect(paused?.state == .paused(elapsed: 283.37))

        let reset = ClockSnapshot(timersValue: nil, stopwatchesValue: stopwatches(state: 1, offset: 0, start: nil))
        #expect(reset.stopwatch == nil)
        #expect(reset.isEmpty)
    }

    @Test func unknownFormatDecodesToNothing() {
        #expect(ClockSnapshot(timersValue: "garbage", stopwatchesValue: ["MTStopwatches": 3]).isEmpty)
        #expect(ClockSnapshot(timersValue: ["MTTimers": [["$MTTimer": ["MTTimerID": "x", "MTTimerState": 3]]]], stopwatchesValue: nil).isEmpty)
    }

    @Test func timerMath() {
        let fire = Date(timeIntervalSince1970: 1_000)
        let timer = ClockTimer(id: "t", title: nil, duration: 100, state: .running(fireDate: fire))
        #expect(timer.remaining(at: fire.addingTimeInterval(-25)) == 25)
        #expect(timer.progress(at: fire.addingTimeInterval(-25)) == 0.75)
        #expect(timer.remaining(at: fire.addingTimeInterval(5)) == 0)
    }
}

@MainActor
struct ClockModuleTests {
    @Test func runningTimerIsActiveAndPausedIsAmbient() {
        let provider = MockClockProvider()
        let module = ClockModule(provider: provider)
        module.start()
        #expect(module.liveActivity?.priority == .active)
        #expect((module.liveActivity?.sideWidth ?? 0) >= 46)                // room for "44:41"

        provider.update(ClockSnapshot(timers: [ClockTimer(id: "p", title: nil, duration: 60, state: .paused(remaining: 30))]))
        #expect(module.liveActivity?.priority == .ambient)

        provider.update(ClockSnapshot())
        #expect(module.liveActivity == nil)
    }

    @Test func finishingTimerShowsToastThenClears() async throws {
        let provider = MockClockProvider(snapshot: ClockSnapshot(timers: [
            ClockTimer(id: "t", title: "Tea", duration: 60, state: .running(fireDate: Date().addingTimeInterval(0.05)))
        ]))
        let module = ClockModule(provider: provider, toastDuration: .milliseconds(100))
        module.start()
        try await Task.sleep(for: .milliseconds(90))
        #expect(module.finishedTimer?.title == "Tea")
        #expect(module.liveActivity?.priority == .transient)
        try await Task.sleep(for: .milliseconds(200))
        #expect(module.finishedTimer == nil)
        #expect(module.liveActivity == nil)
    }
}

struct SpectrumAnalyzerTests {
    private func sine(frequency: Double, amplitude: Float = 0.5, sampleRate: Double = 48_000, count: Int = 48_000 / 2) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    private func lastLevels(for samples: [Float]) -> [Float] {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000, bandCount: 4)
        var last: [Float] = []
        samples.withUnsafeBufferPointer { buffer in
            // Feed in device-sized chunks, like the IO callback does.
            var start = 0
            while start < buffer.count {
                let end = min(start + 512, buffer.count)
                if let levels = analyzer.process(UnsafeBufferPointer(rebasing: buffer[start..<end])) { last = levels }
                start = end
            }
        }
        return last
    }

    @Test func bassLightsTheLowBand() throws {
        let levels = lastLevels(for: sine(frequency: 100))
        try #require(levels.count == 4)
        #expect(levels[0] > 0.5)
        #expect(levels[3] < 0.2)
    }

    @Test func trebleLightsTheHighBand() throws {
        let levels = lastLevels(for: sine(frequency: 7_000))
        try #require(levels.count == 4)
        #expect(levels[3] > 0.5)
        #expect(levels[0] < 0.2)
    }

    @Test func silenceIsFlat() {
        #expect(lastLevels(for: Array(repeating: 0, count: 24_000)).allSatisfy { $0 == 0 })
    }
}

struct MediaSourceFilterTests {
    @Test func onlyMusicAppsByDefault() {
        #expect(MediaSourceFilter.allows("com.spotify.client", includeAllApps: false))
        #expect(MediaSourceFilter.allows("com.apple.Music", includeAllApps: false))
        #expect(!MediaSourceFilter.allows("com.google.Chrome", includeAllApps: false))
        #expect(!MediaSourceFilter.allows("com.apple.Safari", includeAllApps: false))
        #expect(!MediaSourceFilter.allows(nil, includeAllApps: false))
        #expect(MediaSourceFilter.allows("com.google.Chrome", includeAllApps: true))
    }
}
