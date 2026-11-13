import AppKit
import Security

/// Replaces the running Notchi with a newer release.
///
/// Downloads the release's DMG, copies the app out of it, and only swaps it in if it's a valid
/// Notchi that satisfies this copy's own designated requirement: same bundle identifier, signed
/// with the same certificate. So an update can only come from whoever signs Notchi's releases,
/// and macOS sees it as the same app, so its permissions carry over. Then it reopens Notchi.
///
/// An ad-hoc build's requirement is its own exact code hash, which no other build can meet, so
/// ad-hoc builds can't install updates (they fall back to downloading the DMG).
enum UpdateInstaller {
    enum InstallError: LocalizedError {
        case download(Int)
        case noApp
        case notVerified(OSStatus)
        case wrongApp(String)
        case notNewer(String)
        case tool(String, Int32)

        var errorDescription: String? {
            switch self {
            case .download(let code): "The download failed (HTTP \(code))."
            case .noApp: "The download doesn't contain Notchi."
            case .notVerified: "The download isn't signed like this copy of Notchi, so it wasn't installed."
            case .wrongApp(let id): "The download is a different app (\(id))."
            case .notNewer(let version): "The download is version \(version), which isn't newer."
            case .tool(let name, let status): "\(name) failed (\(status))."
            }
        }
    }

    /// Whether this copy can install updates over itself.
    static var canReplaceRunningApp: Bool {
        guard let requirement = ownRequirementString, !requirement.contains("cdhash") else { return false }
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: folder)
    }

    /// This copy's designated requirement, for example
    /// `identifier "dev.notchi.Notchi" and certificate root = H"…"`.
    static var ownRequirementString: String? {
        guard let requirement = ownRequirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }

    private static var ownRequirement: SecRequirement? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    /// Downloads the DMG, checks the app in it and swaps it in for this copy.
    static func install(dmg: URL, version: AppVersion) async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("notchi-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // Download.
        let (downloaded, response) = try await URLSession.shared.download(from: dmg)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw InstallError.download(http.statusCode) }
        let image = work.appendingPathComponent("Notchi.dmg")
        try FileManager.default.moveItem(at: downloaded, to: image)

        // Copy the app out of the disk image.
        let mount = work.appendingPathComponent("mount")
        let staged = work.appendingPathComponent("Notchi.app")
        try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, image.path])
        do {
            let inImage = mount.appendingPathComponent("Notchi.app")
            guard FileManager.default.fileExists(atPath: inImage.path) else { throw InstallError.noApp }
            try await run("/usr/bin/ditto", [inImage.path, staged.path])
        } catch {
            try? await run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
            throw error
        }
        try? await run("/usr/bin/hdiutil", ["detach", mount.path])

        // Check it: same app, same signer, newer.
        try verify(staged, newerThan: version)

        // Swap it in. The running copy keeps working from memory until it relaunches.
        try? await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        _ = try FileManager.default.replaceItemAt(Bundle.main.bundleURL, withItemAt: staged)
    }

    /// Fails unless `app` is a valid, newer Notchi meeting this copy's designated requirement.
    static func verify(_ app: URL, newerThan version: AppVersion) throws {
        guard let requirement = ownRequirement else { throw InstallError.notVerified(errSecCSReqFailed) }
        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else { throw InstallError.notVerified(status) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        status = SecStaticCodeCheckValidity(staticCode, flags, requirement)
        guard status == errSecSuccess else { throw InstallError.notVerified(status) }

        let info = Bundle(url: app)?.infoDictionary
        let identifier = info?["CFBundleIdentifier"] as? String ?? "?"
        guard identifier == Bundle.main.bundleIdentifier else { throw InstallError.wrongApp(identifier) }
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        guard let newVersion = AppVersion(shortVersion), newVersion >= version,
              let current = UpdateChecker.currentVersion, newVersion > current
        else { throw InstallError.notNewer(shortVersion) }
    }

    /// Reopens Notchi from its (new) bundle once this process has quit, then quits.
    @MainActor
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundleURL.path
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$1\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", path]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InstallError.tool(URL(fileURLWithPath: tool).lastPathComponent, process.terminationStatus))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
