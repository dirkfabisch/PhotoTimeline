import AppKit
import SwiftUI

/// Remembers the size of the last resized document window and applies it to new ones.
struct WindowSizeMemory: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TrackingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TrackingView: NSView {
        private static let key = "documentWindowSize"
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }

            if let saved = UserDefaults.standard.string(forKey: Self.key) {
                let size = NSSizeFromString(saved)
                // SwiftUI sizes the window after it's attached, so apply ours afterwards.
                if size.width > 0, size.height > 0 {
                    DispatchQueue.main.async { [weak window] in
                        guard let window else { return }
                        // Keep the top-left corner where the system placed the window.
                        var frame = window.frame
                        frame.origin.y += frame.height - size.height
                        frame.size = size
                        window.setFrame(frame, display: true)
                    }
                }
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated {
                    guard let window, !window.styleMask.contains(.fullScreen) else { return }
                    UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: Self.key)
                }
            }
        }
    }
}
