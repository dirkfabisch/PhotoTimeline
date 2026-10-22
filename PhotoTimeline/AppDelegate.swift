import AppKit

/// Reopens the documents that were open when the app quit. If none were open,
/// the usual Open panel appears at launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let key = "openDocumentBookmarks"

    /// Resolved before the scenes are built, so the launch Open panel can be suppressed.
    static let documentsToRestore: [URL] = {
        let bookmarks = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        return bookmarks.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                     bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { return nil }
            return url
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let urls = Self.documentsToRestore
        guard !urls.isEmpty else { return }
        var remaining = urls.count
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in
                remaining -= 1
                // Nothing could be reopened: fall back to the Open panel that was suppressed.
                if remaining == 0, NSDocumentController.shared.documents.isEmpty {
                    NSDocumentController.shared.openDocument(nil)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let bookmarks = NSDocumentController.shared.documents.compactMap {
            try? $0.fileURL?.bookmarkData(options: .withSecurityScope)
        }
        UserDefaults.standard.set(bookmarks, forKey: Self.key)
    }
}
