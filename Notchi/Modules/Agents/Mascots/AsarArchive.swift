import Foundation

/// Reads files out of an Electron `.asar` archive, the way Claude.app and the Codex app package
/// their web content (and with it, their mascots' sprites).
///
/// The format: a little-endian u32 (4), the header's size, then the header (a Chromium pickle: its
/// size, the JSON's length, the JSON), then the files back to back. The JSON is a tree of
/// `{"files": {name: {…}}}` with each file's `offset` (a string) and `size`.
struct AsarArchive: @unchecked Sendable {
    let url: URL
    /// Every packed file's path ("/webview/assets/x.js") with its offset and size.
    let entries: [String: (offset: UInt64, size: Int)]
    private let base: UInt64

    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 16), prefix.count == 16 else { return nil }
        let headerSize = UInt64(Self.uint32(prefix, at: 4))
        let jsonLength = Int(Self.uint32(prefix, at: 12))
        guard jsonLength > 0, let json = try? handle.read(upToCount: jsonLength), json.count == jsonLength,
              let tree = JSONObject.decode(json) else { return nil }
        var entries: [String: (offset: UInt64, size: Int)] = [:]
        Self.collect(tree, prefix: "", into: &entries)
        self.url = url
        self.entries = entries
        base = 8 + headerSize
    }

    /// Paths of packed files, filtered by `predicate`.
    func paths(where predicate: (String) -> Bool) -> [String] {
        entries.keys.filter(predicate).sorted()
    }

    func data(at path: String) -> Data? {
        guard let entry = entries[path], let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: base + entry.offset)) != nil else { return nil }
        return try? handle.read(upToCount: entry.size)
    }

    private static func collect(_ node: JSONObject, prefix: String, into entries: inout [String: (offset: UInt64, size: Int)]) {
        for (name, value) in node.object("files") ?? [:] {
            guard let child = value as? JSONObject else { continue }
            let path = "\(prefix)/\(name)"
            if child["files"] != nil {
                collect(child, prefix: path, into: &entries)
            } else if child["unpacked"] as? Bool != true, let offset = child.string("offset").flatMap(UInt64.init),
                      let size = (child["size"] as? NSNumber)?.intValue {
                entries[path] = (offset, size)
            }
        }
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }
}
