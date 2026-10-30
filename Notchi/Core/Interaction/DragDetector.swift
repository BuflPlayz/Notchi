import AppKit

/// Notices when the user is dragging something (files, an image, text) anywhere on screen, so the
/// notch can open to take it.
///
/// A drag session writes to the drag pasteboard, so a mouse drag that started after the pasteboard
/// changed is carrying something. Global monitors only see events going to other apps, so drags
/// out of Notchi's own panel (an item leaving the Shelf) don't count. Monitors fire only while the
/// mouse is pressed or moving, so this costs nothing at rest.
@MainActor
final class DragDetector {
    /// Called when a drag starts (true) or ends (false).
    var onChange: ((Bool) -> Void)?
    private(set) var isDragging = false

    private let pasteboard = NSPasteboard(name: .drag)
    private var changeCountAtMouseDown = 0
    private var monitors: [Any] = []

    func start() {
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.changeCountAtMouseDown = self.pasteboard.changeCount
                self.setDragging(false)
            }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isDragging else { return }
                if self.pasteboard.changeCount != self.changeCountAtMouseDown { self.setDragging(true) }
            }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.setDragging(false) }
        }
        monitors = [down, dragged, up].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        setDragging(false)
    }

    private func setDragging(_ dragging: Bool) {
        guard dragging != isDragging else { return }
        isDragging = dragging
        onChange?(dragging)
    }
}
