import AppKit
import SwiftUI

/// Hosting view for the notch panel's SwiftUI content.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        // Don't let SwiftUI's ideal size resize the panel; the window controller owns the frame.
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Buttons respond to the first click even though the panel never activates the app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The panel deliberately covers the camera housing. Left alone, AppKit reports notch safe-area
    /// insets that SwiftUI would push the content down by.
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
}
