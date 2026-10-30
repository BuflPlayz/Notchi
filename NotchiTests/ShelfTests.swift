import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Notchi

@MainActor
struct ShelfTests {
    private let defaults = UserDefaults(suiteName: "notchi.tests.\(UUID().uuidString)")!
    private let storage = URL.temporaryDirectory.appending(path: "NotchiShelfTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func makeFile(_ name: String = "Notes.txt") throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data("hello".utf8).write(to: url)
        return url
    }

    @Test func droppedFilesStayWhereTheyAre() throws {
        let shelf = ShelfModule(defaults: defaults, storageDirectory: storage)
        let file = try makeFile()
        shelf.add(fileAt: file)
        shelf.add(fileAt: file)
        #expect(shelf.items.map(\.url) == [file])

        // Removing a file the user owns only forgets it.
        shelf.remove(shelf.items[0])
        #expect(shelf.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func nonFilesGetTheirOwnFileThatRemovingDeletes() throws {
        let shelf = ShelfModule(defaults: defaults, storageDirectory: storage)
        let item = try shelf.add(data: Data("hi".utf8), named: "Text.txt")
        #expect(item.isOwned)
        #expect(item.name == "Text.txt")
        #expect(try Data(contentsOf: item.url) == Data("hi".utf8))

        // Same name again doesn't clash.
        let second = try shelf.add(data: Data("again".utf8), named: "Text.txt")
        #expect(second.url != item.url)

        shelf.removeAll()
        #expect(!FileManager.default.fileExists(atPath: item.url.path))
        #expect(!FileManager.default.fileExists(atPath: second.url.path))
    }

    @Test func itemsSurviveRelaunchUnlessTheFileIsGone() throws {
        let kept = try makeFile("Kept.txt")
        let deleted = try makeFile("Deleted.txt")
        let shelf = ShelfModule(defaults: defaults, storageDirectory: storage)
        shelf.add(fileAt: kept)
        shelf.add(fileAt: deleted)
        try FileManager.default.removeItem(at: deleted)

        let relaunched = ShelfModule(defaults: defaults, storageDirectory: storage)
        #expect(relaunched.items.map(\.url) == [kept])
    }

    @Test func loaderPrefersFilesThenImagesThenLinksThenText() async throws {
        let file = try makeFile()
        #expect(await ShelfDropLoader.load(NSItemProvider(contentsOf: file)!) == .file(file))

        let link = NSItemProvider(object: URL(string: "https://example.com/page")! as NSURL)
        guard case .data(let plist, let name)? = await ShelfDropLoader.load(link) else {
            Issue.record("A link should become a .webloc")
            return
        }
        #expect(name.hasSuffix(".webloc"))
        let dictionary = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: String]
        #expect(dictionary?["URL"] == "https://example.com/page")

        let text = NSItemProvider(object: "Remember this" as NSString)
        #expect(await ShelfDropLoader.load(text) == .data(Data("Remember this".utf8), name: "Text.txt"))
    }

    @Test func fileNamesAreSafeAndHaveExtensions() {
        #expect(ShelfDropLoader.fileName("a/b:c", fallback: "x", extension: "png") == "a-b-c.png")
        #expect(ShelfDropLoader.fileName("photo.jpg", fallback: "x", extension: "png", keeping: .image) == "photo.jpg")
        #expect(ShelfDropLoader.fileName("example.com", fallback: "x", extension: "webloc") == "example.com.webloc")
        #expect(ShelfDropLoader.fileName("notes.TXT", fallback: "x", extension: "txt") == "notes.TXT")
        #expect(ShelfDropLoader.fileName(nil, fallback: "Image", extension: "png") == "Image.png")
    }

    @Test func draggingOntoTheNotchOpensTheShelf() {
        let registry = ModuleRegistry(defaults: defaults)
        registry.register(ShelfModule(defaults: defaults, storageDirectory: storage))
        let model = NotchViewModel(geometry: .previewNotch, registry: registry)

        // A plain hover with the default delay doesn't open at once; a drag does.
        model.setDragging(true)
        model.hoverChanged(isInside: true)
        #expect(model.state == .expanded)
        #expect(model.selectedModule?.id == "shelf")
        #expect(model.dropHandler?.id == "shelf")
    }
}
