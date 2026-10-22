import Foundation

/// Resolves security-scoped bookmarks and keeps access open while the document lives.
nonisolated final class BookmarkStore {
    private var urls: [UUID: URL] = [:]

    deinit {
        for url in urls.values { url.stopAccessingSecurityScopedResource() }
    }

    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Returns the file URL, or nil if the file is gone. `refreshed` receives new
    /// bookmark data when the stored one was stale (file moved/renamed).
    func url(for photo: PhotoRef, refreshed: (Data) -> Void = { _ in }) -> URL? {
        if let url = urls[photo.id] { return url }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: photo.bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let data = try? Self.makeBookmark(for: url) { refreshed(data) }
        urls[photo.id] = url
        return url
    }

    func forget(_ id: UUID) {
        urls.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
    }
}
