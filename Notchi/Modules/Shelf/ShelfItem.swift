import Foundation

/// One thing kept on the Shelf: a file the user dropped (left where it is), or a file Notchi wrote
/// for something that wasn't one (an image, a link or text dragged from a browser).
struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let url: URL
    /// Notchi wrote this file, so it's deleted when the item is removed.
    let isOwned: Bool

    var name: String { url.lastPathComponent }
}
