import AppKit
import SwiftUI

/// Opens document windows centered on their screen, covering 80 % of its usable area.
struct WindowPlacement: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { PlacingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class PlacingView: NSView {
        private var placed = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !placed, let window else { return }
            placed = true
            // Place right away so the window never shows at its default size, and again after
            // SwiftUI has applied its own sizing.
            Self.place(window)
            DispatchQueue.main.async { [weak window] in
                if let window { Self.place(window) }
            }
        }

        private static func place(_ window: NSWindow) {
            guard let screen = window.screen ?? NSScreen.main else { return }
            let area = screen.visibleFrame
            let size = CGSize(width: area.width * 0.8, height: area.height * 0.8)
            window.setFrame(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                   width: size.width, height: size.height), display: true)
        }
    }
}
