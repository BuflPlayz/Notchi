import AppKit
import OSLog

/// Tells people when a newer Notchi is out.
///
/// Asks GitHub for the latest published release a little after launch and then once a day, and
/// offers to download it when it's newer than the running version. It doesn't install anything:
/// "Download" fetches the DMG, and the new app replaces this one by dragging it onto Applications.
/// Settings › About has the switch for automatic checks and a "Check for Updates" button.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// A published release.
    struct Release: Equatable, Sendable {
        var version: AppVersion
        /// The release page on GitHub.
        var pageURL: URL
        /// The DMG, when the release has one.
        var downloadURL: URL?
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case failed
    }

    private(set) var status = Status.idle
    private(set) var lastChecked: Date? = UserDefaults.standard.object(forKey: Preferences.Key.lastUpdateCheck) as? Date

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.notchi.Notchi", category: "Updates")

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/BuflPlayz/Notchi/releases/latest")!
    /// Out of the way of the permission prompts at launch.
    private static let launchDelay: Duration = .seconds(15)
    private static let interval: TimeInterval = 24 * 60 * 60

    static var currentVersion: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    private init() {}

    /// Starts the automatic checks: one shortly after launch (unless one ran in the last day),
    /// then daily while Notchi runs.
    func start() {
        launchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.launchDelay)
            guard let self, !Task.isCancelled else { return }
            if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.interval { return }
            await self.check(userInitiated: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.check(userInitiated: false) }
            }
        }
    }

    /// Checks now. Automatic checks stay quiet unless there's an update the user hasn't skipped;
    /// a check from the button always answers.
    func check(userInitiated: Bool) async {
        guard userInitiated || Preferences.checkForUpdates else { return }
        guard status != .checking, let current = Self.currentVersion else { return }
        status = .checking
        do {
            let release = try await fetchLatestRelease()
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Preferences.Key.lastUpdateCheck)
            guard release.version > current else {
                logger.notice("Up to date: \(current.description, privacy: .public), latest \(release.version.description, privacy: .public)")
                status = .upToDate
                if userInitiated { showUpToDate(current) }
                return
            }
            logger.notice("Update available: \(release.version.description, privacy: .public)")
            status = .available(release)
            let skipped = UserDefaults.standard.string(forKey: Preferences.Key.skippedUpdateVersion)
            if userInitiated || skipped != release.version.description {
                prompt(for: release, current: current)
            }
        } catch {
            logger.error("Update check failed: \(String(describing: error), privacy: .public)")
            status = .failed
            if userInitiated { showFailure() }
        }
    }

    /// Opens the DMG download, or the release page if it has no DMG.
    func download(_ release: Release) {
        NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
    }

    // MARK: GitHub

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]
    }

    private enum CheckError: Error {
        case badResponse(Int)
        case badVersion(String)
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Notchi/\(Self.currentVersion?.description ?? "?")", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw CheckError.badResponse(code) }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let version = AppVersion(release.tag_name) else { throw CheckError.badVersion(release.tag_name) }
        let dmg = release.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url
        return Release(version: version, pageURL: release.html_url, downloadURL: dmg)
    }

    // MARK: Alerts

    private func prompt(for release: Release, current: AppVersion) {
        let alert = NSAlert()
        alert.messageText = "Notchi \(release.version) is available"
        alert.informativeText = "You have \(current). Download the new version, open it, and drag Notchi onto Applications to replace this one. Your settings stay as they are."
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        switch run(alert) {
        case .alertFirstButtonReturn:
            download(release)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version.description, forKey: Preferences.Key.skippedUpdateVersion)
        default:
            break
        }
    }

    private func showUpToDate(_ current: AppVersion) {
        let alert = NSAlert()
        alert.messageText = "Notchi is up to date"
        alert.informativeText = "Version \(current) is the latest."
        alert.icon = NSApp.applicationIconImage
        run(alert)
    }

    private func showFailure() {
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = "Check your internet connection and try again."
        alert.icon = NSApp.applicationIconImage
        run(alert)
    }

    /// Notchi has no Dock icon, so bring it forward for the alert or it opens behind other apps.
    @discardableResult
    private func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }
}

/// A dotted version like "0.3.1", compared number by number. Accepts a leading "v".
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let parts: [Int]

    init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    /// Missing parts count as 0, so 0.3 equals 0.3.0.
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
