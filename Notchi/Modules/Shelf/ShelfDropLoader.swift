import AppKit
import UniformTypeIdentifiers

/// Reads what was dropped on the notch: files stay where they are; images, links and text become
/// data for a new file, so everything on the Shelf can be dragged back out as a file.
@MainActor
enum ShelfDropLoader {
    /// What a drop target registers for.
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .plainText]

    enum Loaded: Equatable {
        case file(URL)
        case data(Data, name: String)
    }

    /// Files first; then an image over its link (dragging a picture from a browser offers both);
    /// then a link (saved as a `.webloc`); then plain text.
    static func load(_ provider: NSItemProvider) async -> Loaded? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider), url.isFileURL {
            return .file(url)
        }
        // SwiftUI hands a dragged file over as its content type (a .txt as plain text), not as a
        // file URL. Asking for it in place gets the original file back; anything that isn't a file
        // comes back as a temporary copy instead, and falls through to the cases below.
        if let type = provider.registeredTypeIdentifiers.first, let url = await loadInPlaceFile(provider, type: type) {
            return .file(url)
        }
        if let type = provider.registeredTypeIdentifiers.compactMap(UTType.init).first(where: { $0.conforms(to: .image) }),
           let data = await loadData(provider, type: type) {
            return .data(data, name: fileName(provider.suggestedName, fallback: "Image", extension: type.preferredFilenameExtension ?? "png", keeping: .image))
        }
        if provider.canLoadObject(ofClass: URL.self), let url = await loadURL(provider) {
            guard let plist = try? PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)
            else { return nil }
            return .data(plist, name: fileName(provider.suggestedName, fallback: url.host() ?? "Link", extension: "webloc"))
        }
        if provider.canLoadObject(ofClass: String.self), let text = await loadString(provider) {
            return .data(Data(text.utf8), name: fileName(provider.suggestedName, fallback: "Text", extension: "txt"))
        }
        return nil
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

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    /// The original file, if the provider is a file that can be opened in place.
    private static func loadInPlaceFile(_ provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, isInPlace, _ in
                continuation.resume(returning: isInPlace ? url : nil)
            }
        }
    }

    private static func loadString(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in continuation.resume(returning: text) }
        }
    }

    private static func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
