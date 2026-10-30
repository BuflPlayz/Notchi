import AppKit
import SwiftUI

/// A temporary shelf in the notch. Drag files (or images, links, text) onto the notch to keep them
/// here, then drag them back out wherever they're needed. Dropping on Share instead opens the
/// share menu (AirDrop, Messages, Mail…) for them.
///
/// Dropped files stay where they are; the Shelf only remembers them. Things that weren't files are
/// written to Application Support, and deleted again when they're removed from the Shelf.
@MainActor
@Observable
final class ShelfModule: NotchModule, NotchDropHandler {
    let id = "shelf"
    let title = "Shelf"
    let symbol = "tray.full"
    /// The Shelf never takes compact mode: it's there when you open the notch.
    let liveActivity: LiveActivity? = nil

    private(set) var items: [ShelfItem] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageDirectory: URL

    static let itemsKey = "shelfItems"

    static var defaultStorageDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Notchi/Shelf", directoryHint: .isDirectory)
    }

    /// - Parameters:
    ///   - defaults: Where the list is remembered; tests pass a throwaway suite.
    ///   - storageDirectory: Where files for images, links and text are written.
    init(defaults: UserDefaults = .standard, storageDirectory: URL = ShelfModule.defaultStorageDirectory) {
        self.defaults = defaults
        self.storageDirectory = storageDirectory
        load()
    }

    // MARK: Items

    /// Keeps a file where it is. Dropping the same file twice keeps one.
    func add(fileAt url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        withAnimation(Motion.content) { items.append(ShelfItem(id: UUID(), url: url, isOwned: false)) }
        save()
    }

    /// Writes something that wasn't a file to its own file, and keeps that.
    @discardableResult
    func add(data: Data, named name: String) throws -> ShelfItem {
        let url = try write(data, named: name, in: storageDirectory)
        let item = ShelfItem(id: UUID(), url: url, isOwned: true)
        withAnimation(Motion.content) { items.append(item) }
        save()
        return item
    }

    func remove(_ item: ShelfItem) {
        withAnimation(Motion.content) { items.removeAll { $0.id == item.id } }
        if item.isOwned { try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent()) }
        save()
    }

    func removeAll() {
        items.forEach { if $0.isOwned { try? FileManager.default.removeItem(at: $0.url.deletingLastPathComponent()) } }
        withAnimation(Motion.content) { items.removeAll() }
        save()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func showInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func share(_ item: ShelfItem) {
        Self.presentSharing([item.url])
    }

    // MARK: Drops

    /// Keeps everything dropped on the Shelf zone.
    func store(_ providers: [NSItemProvider]) {
        Task {
            for provider in providers {
                switch await ShelfDropLoader.load(provider) {
                case .file(let url): add(fileAt: url)
                case .data(let data, let name): _ = try? add(data: data, named: name)
                case nil: break
                }
            }
        }
    }

    /// Opens the share menu for everything dropped on the Share zone. Things that weren't files are
    /// written to a temporary folder first, since sharing services take files.
    func share(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                switch await ShelfDropLoader.load(provider) {
                case .file(let url): urls.append(url)
                case .data(let data, let name):
                    let folder = URL.temporaryDirectory.appending(path: "Notchi Share", directoryHint: .isDirectory)
                    if let url = try? write(data, named: name, in: folder) { urls.append(url) }
                case nil: break
                }
            }
            Self.presentSharing(urls)
        }
    }

    /// The share menu, at the cursor, anchored to the notch's panel.
    private static func presentSharing(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = NSApp.windows.first(where: { $0 is NotchPanel }), let view = panel.contentView else { return }
        let point = view.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        NSApp.activate()
        NSSharingServicePicker(items: urls).show(relativeTo: NSRect(origin: point, size: .zero).insetBy(dx: -1, dy: -1), of: view, preferredEdge: .minY)
    }

    // MARK: NotchModule views

    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(ShelfView(module: self)) }
    func dropView() -> AnyView { AnyView(ShelfDropView(module: self)) }

    // MARK: Storage

    /// Each file gets its own folder, so names never clash and it keeps its original name when
    /// dragged back out.
    private func write(_ data: Data, named name: String, in directory: URL) throws -> URL {
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        try data.write(to: url)
        return url
    }

    /// Restores the list, leaving out files that have since been moved or deleted.
    private func load() {
        guard let data = defaults.data(forKey: Self.itemsKey),
              let saved = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return }
        items = saved.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        if items.count != saved.count { save() }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(items), forKey: Self.itemsKey)
    }
}
