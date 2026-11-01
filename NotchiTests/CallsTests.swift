import Foundation
import Testing
@testable import Notchi

struct IncomingCallTests {
    @Test func readsACallAlert() throws {
        let call = try #require(IncomingCall(
            texts: ["FaceTime", "Jane Appleseed", "FaceTime Audio"],
            controls: ["Decline", "Accept", "Options"]
        ))
        #expect(call.caller == "Jane Appleseed")
        #expect(call.detail == "FaceTime Audio")
        #expect(call.appBundleID == CallApps.faceTime)
    }

    @Test func needsBothAcceptAndDecline() {
        #expect(IncomingCall(texts: ["Messages", "Jane", "On my way"], controls: ["Reply", "Close"]) == nil)
        #expect(IncomingCall(texts: ["Jane"], controls: ["Accept"]) == nil)
        #expect(IncomingCall(texts: ["+1 555 0100", "iPhone"], controls: ["Answer", "Decline"])?.appBundleID == CallApps.phone)
    }

    @Test func skipsButtonLabelsAndRepeats() throws {
        let call = try #require(IncomingCall(texts: ["Accept", "Mum", "Mum", "Decline"], controls: ["accept", "decline"]))
        #expect(call.caller == "Mum")
        #expect(call.detail == nil)
        #expect(IncomingCall(texts: [], controls: ["Accept", "Decline"])?.caller == "Incoming Call")
    }

    @Test func customActionNames() {
        #expect(IncomingCall.actionLabel("Name:Accept\nTarget:0x0\nSelector:(null)") == "Accept")
        #expect(IncomingCall.actionLabel("AXPress") == "AXPress")
    }
}

struct CallAppsTests {
    private func use(_ bundleID: String?, process: String = "app") -> MicrophoneUse {
        MicrophoneUse(pid: 1, bundleID: bundleID, processName: process, since: Date())
    }

    @Test func callingApps() {
        #expect(CallApps.isCall(use("us.zoom.xos"), includeBrowsers: false))
        #expect(CallApps.isCall(use(nil, process: "avconferenced"), includeBrowsers: false))
        #expect(CallApps.isCall(use("com.apple.avconferenced"), includeBrowsers: false))
        #expect(!CallApps.isCall(use("com.apple.VoiceMemos"), includeBrowsers: true))
    }

    @Test func browsersOnlyWhenAsked() {
        #expect(CallApps.isCall(use("com.google.Chrome"), includeBrowsers: true))
        #expect(!CallApps.isCall(use("com.google.Chrome"), includeBrowsers: false))
        // Never a recording either way: a browser recording isn't the kind of thing to show.
        #expect(!CallApps.isRecording(use("com.google.Chrome")))
    }
}

@MainActor
struct CallsModuleTests {
    private func zoom(startedAgo seconds: TimeInterval) -> MicrophoneUse {
        MicrophoneUse(pid: 4242, bundleID: "us.zoom.xos", processName: "zoom.us", since: Date().addingTimeInterval(-seconds))
    }

    @Test func callComesAndGoesWithItsMicrophone() async throws {
        let module = CallsModule(toastDuration: .milliseconds(200), endDelay: .milliseconds(50))
        let use = zoom(startedAgo: 30)
        module.apply([use])
        #expect(module.call?.appBundleID == "us.zoom.xos")
        #expect(module.call?.since == use.since)
        #expect(module.liveActivity?.priority == .active)
        #expect(module.showsInPanel)

        module.apply([])
        #expect(module.call != nil)                        // a grace period first
        try await Task.sleep(for: .milliseconds(120))
        #expect(module.call == nil)
        #expect(module.ended?.appName != nil)
        #expect(module.liveActivity?.priority == .transient)
        try await Task.sleep(for: .milliseconds(300))
        #expect(module.liveActivity == nil)
        #expect(!module.showsInPanel)
    }

    @Test func microphoneBackWithinGraceKeepsTheCall() async throws {
        let module = CallsModule(endDelay: .milliseconds(80))
        let use = zoom(startedAgo: 60)
        module.apply([use])
        module.apply([])
        module.apply([MicrophoneUse(pid: use.pid, bundleID: use.bundleID, processName: use.processName, since: Date())])
        try await Task.sleep(for: .milliseconds(150))
        #expect(module.call?.since == use.since)           // the same call, same running time
        #expect(module.ended == nil)
    }

    @Test func shortCallsEndQuietly() async throws {
        let module = CallsModule(endDelay: .milliseconds(20))
        module.apply([zoom(startedAgo: 0)])
        module.apply([])
        try await Task.sleep(for: .milliseconds(80))
        #expect(module.ended == nil)
        #expect(module.liveActivity == nil)
    }

    @Test func ringingTakesTheMiddle() {
        let module = CallsModule()
        module.apply([zoom(startedAgo: 10)])
        module.applyIncoming(IncomingCall(caller: "Jane Appleseed", detail: nil, appBundleID: CallApps.faceTime))
        #expect(module.liveActivity?.priority == .urgent)
        #expect(module.liveActivity?.showsInFullScreen == true)
        module.applyIncoming(nil)
        #expect(module.liveActivity?.priority == .active)
    }

    @Test func callerWidthIsCapped() {
        #expect(CallMetrics.callerWidth("Al") == 56)
        #expect(CallMetrics.callerWidth(String(repeating: "x", count: 60)) == Metrics.maxCompactSideWidth)
    }
}
