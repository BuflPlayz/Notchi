import QuickLookThumbnailing
import SwiftUI

// MARK: - Shelf page

/// The Shelf's page in the expanded panel: kept items in a row, each one draggable back out.
struct ShelfView: View {
    let module: ShelfModule

    var body: some View {
        if module.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 22, weight: .medium))
                Text("Drag files onto the notch to keep them here")
                    .font(Theme.body)
            }
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(module.items.count == 1 ? "1 item" : "\(module.items.count) items")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("Clear") { module.removeAll() }
                        .buttonStyle(.plain)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondary)
                        .help("Remove everything from the Shelf")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(module.items) { item in
                            ShelfItemTile(module: module, item: item)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }
}

/// A kept item: its thumbnail and name. Drag it out to use it, click to open it, right-click for more.
private struct ShelfItemTile: View {
    let module: ShelfModule
    let item: ShelfItem
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 5) {
            ShelfThumbnail(url: item.url)
                .frame(width: 52, height: 52)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 70, height: 26, alignment: .top)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? Theme.controlFill : .clear)
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button { module.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.primary, Color(white: 0.25))
                }
                .buttonStyle(.plain)
                .help("Remove from the Shelf")
                .offset(x: 2, y: -2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture { module.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { module.open(item) }
            Button("Show in Finder") { module.showInFinder(item) }
            Button("Share…") { module.share(item) }
            Divider()
            Button("Remove from Shelf") { module.remove(item) }
        }
        .help(item.name)
    }
}

/// Quick Look's thumbnail for a file, or its Finder icon until that's ready (or if there's none).
private struct ShelfThumbnail: View {
    let url: URL
    @State private var thumbnail: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .task(id: url) {
            let image = await Self.render(url, size: 52, scale: displayScale)
            thumbnail = image.map { NSImage(cgImage: $0, size: .zero) }
        }
    }

    nonisolated private static func render(_ url: URL, size: CGFloat, scale: CGFloat) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }
}

// MARK: - Drop targets

/// Shown while something is dragged over the open notch: keep it on the Shelf, or share it.
struct ShelfDropView: View {
    let module: ShelfModule

    var body: some View {
        HStack(spacing: 10) {
            DropZone(symbol: "tray.and.arrow.down.fill", title: "Shelf", subtitle: "Keep it here for later") {
                module.store($0)
            }
            DropZone(symbol: "square.and.arrow.up", title: "Share", subtitle: "AirDrop, Messages, Mail…") {
                module.share($0)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A rounded drop target that lights up while something is held over it.
private struct DropZone: View {
    let symbol: String
    let title: String
    let subtitle: String
    let perform: ([ShelfDropLoader.Loaded]) -> Void
    @State private var isTargeted = false
    @Environment(\.notchDropFinished) private var dropFinished

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .symbolEffect(.bounce, value: isTargeted)
            Text(title)
                .font(Theme.title)
            Text(subtitle)
                .font(Theme.caption)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { shape.fill(isTargeted ? Theme.controlFillPressed : Theme.controlFill) }
        .overlay {
            shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(isTargeted ? Theme.primary : Theme.tertiary)
        }
        .scaleEffect(isTargeted ? 1.03 : 1)
        .animation(Motion.content, value: isTargeted)
        .overlay {
            PasteboardDropTarget(isTargeted: $isTargeted) { pasteboard in
                let items = ShelfDropLoader.items(from: pasteboard)
                guard !items.isEmpty else { return false }
                perform(items)
                dropFinished()
                return true
            }
        }
    }
}

/// An AppKit drop target, so drops are read off the pasteboard the moment they land (see
/// `ShelfDropLoader` for why not SwiftUI's `onDrop`).
private struct PasteboardDropTarget: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: (NSPasteboard) -> Bool

    func makeNSView(context: Context) -> TargetView {
        let view = TargetView()
        view.registerForDraggedTypes(ShelfDropLoader.acceptedTypes)
        return view
    }

    func updateNSView(_ view: TargetView, context: Context) {
        view.onTargetChange = { targeted in isTargeted = targeted }
        view.onDrop = onDrop
    }

    final class TargetView: NSView {
        var onTargetChange: ((Bool) -> Void)?
        var onDrop: ((NSPasteboard) -> Bool)?

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            onTargetChange?(true)
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            onTargetChange?(false)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            onTargetChange?(false)
            return onDrop?(sender.draggingPasteboard) ?? false
        }
    }
}
