import Testing
@testable import Notchi

struct AppVersionTests {
    @Test func parsesTagsAndBundleVersions() {
        #expect(AppVersion("v0.3.1")?.parts == [0, 3, 1])
        #expect(AppVersion("0.3.0")?.parts == [0, 3, 0])
        #expect(AppVersion("1.2")?.description == "1.2")
        #expect(AppVersion("0.3.0-beta") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("v") == nil)
    }

    @Test func comparesNumberByNumber() {
        #expect(AppVersion("0.3.1")! > AppVersion("0.3.0")!)
        #expect(AppVersion("0.10.0")! > AppVersion("0.9.9")!)   // not string order
        #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        #expect(AppVersion("0.3")! == AppVersion("0.3.0")!)
        #expect(!(AppVersion("v0.3.0")! > AppVersion("0.3.0")!))
    }
}
