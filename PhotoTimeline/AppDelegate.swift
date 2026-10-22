import AppKit

/// Reopens the documents that were open when the app quit. If none were open,
/// the usual Open panel appears at launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let key = "openDocumentBookmarks"
    private var restore: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        let bookmarks = UserDefaults.standard.array(forKey: Self.key) as? [Data] ?? []
        restore = bookmarks.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                     bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { return nil }
            return url
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for url in restore {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        restore.isEmpty
    }

    func applicationWillTerminate(_ notification: Notification) {
        let bookmarks = NSDocumentController.shared.documents.compactMap {
            try? $0.fileURL?.bookmarkData(options: .withSecurityScope)
        }
        UserDefaults.standard.set(bookmarks, forKey: Self.key)
    }
}
