import AppKit
import UniformTypeIdentifiers

/// Reads what was dropped on the notch straight off the drag pasteboard: files stay where they
/// are; images, links and text become data for a new file, so everything on the Shelf can be
/// dragged back out as a file.
///
/// The drop targets are AppKit views reading the pasteboard synchronously. SwiftUI's `onDrop` held
/// the drag image on screen for about half a second after every drop in the notch's panel, and
/// handed files over as their contents (a .txt as plain text) rather than as files.
@MainActor
enum ShelfDropLoader {
    /// What the drop targets register for.
    static let acceptedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .string] + NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }

    enum Loaded: Equatable {
        case file(URL)
        case data(Data, name: String)
    }

    /// Files first; then an image over its link (dragging a picture from a browser offers both);
    /// then a link (saved as a `.webloc`); then plain text.
    static func items(from pasteboard: NSPasteboard) -> [Loaded] {
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !files.isEmpty {
            return files.map(Loaded.file)
        }
        let link = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first
        if let type = pasteboard.types?.first(where: { UTType($0.rawValue)?.conforms(to: .image) == true }),
           let data = pasteboard.data(forType: type) {
            let ext = UTType(type.rawValue)?.preferredFilenameExtension ?? "png"
            // A browser image's own name comes from its address.
            let name = link.map(\.lastPathComponent).flatMap { $0.isEmpty || $0 == "/" ? nil : $0 }
            return [.data(data, name: fileName(name, fallback: "Image", extension: ext, keeping: .image))]
        }
        if let link {
            guard let plist = try? PropertyListSerialization.data(fromPropertyList: ["URL": link.absoluteString], format: .xml, options: 0)
            else { return [] }
            return [.data(plist, name: fileName(link.host(), fallback: "Link", extension: "webloc"))]
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return [.data(Data(text.utf8), name: "Text.txt")]
        }
        return []
    }

    /// A file name that's safe on disk and ends in `ext`. A name's own extension stays only if it's
    /// already a `kind` (a photo's ".jpg" for an image); otherwise "example.com" would pass as one.
    static func fileName(_ suggested: String?, fallback: String, extension ext: String, keeping kind: UTType? = nil) -> String {
        let base = (suggested?.isEmpty == false ? suggested! : fallback)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let existing = (base as NSString).pathExtension.lowercased()
        if existing == ext.lowercased() { return base }
        if let kind, UTType(filenameExtension: existing)?.conforms(to: kind) == true { return base }
        return "\(base).\(ext)"
    }
}
