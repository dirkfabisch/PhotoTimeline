import SwiftUI
import Synchronization
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let photoTimeline = UTType(exportedAs: "de.fabisch.phototimeline")
}

/// ReferenceFileDocument is Sendable, so the class itself can't be main-actor bound.
/// `photos` is only touched from the main actor (editing API is `@MainActor`).
/// AppKit takes snapshots on a background queue while saving, so those read a
/// lock-protected copy instead.
final class TimelineDocument: ReferenceFileDocument, @unchecked Sendable {
    nonisolated static var readableContentTypes: [UTType] { [.photoTimeline] }

    @Published var photos: [PhotoRef] {
        didSet { saved.withLock { [photos] in $0 = photos } }
    }
    private let saved: Mutex<[PhotoRef]>
    let bookmarks = BookmarkStore()

    init() {
        saved = Mutex([])
        photos = []
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let photos = try decoder.decode(FileFormat.self, from: data).photos
        saved = Mutex(photos)
        _photos = Published(initialValue: photos)
    }

    nonisolated func snapshot(contentType: UTType) throws -> [PhotoRef] {
        saved.withLock { $0 }
    }

    nonisolated func fileWrapper(snapshot: [PhotoRef], configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return FileWrapper(regularFileWithContents: try encoder.encode(FileFormat(photos: snapshot)))
    }

    private nonisolated struct FileFormat: Codable {
        var version = 1
        var photos: [PhotoRef]
    }

    // MARK: Access

    @MainActor
    func url(for photo: PhotoRef) -> URL? {
        bookmarks.url(for: photo) { [weak self] data in
            guard let self, let i = photos.firstIndex(where: { $0.id == photo.id }) else { return }
            photos[i].bookmark = data
        }
    }

    // MARK: Editing (every change registers undo, which also marks the document dirty)

    /// Adds dropped files and folders. Returns the number of images added.
    @MainActor @discardableResult
    func add(_ urls: [URL], undoManager: UndoManager?) -> Int {
        let known = Set(photos.compactMap { url(for: $0)?.standardizedFileURL })
        var seen = known
        var added: [PhotoRef] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            for file in Self.imageFiles(in: url) where seen.insert(file.standardizedFileURL).inserted {
                guard let info = CaptureDateReader.read(file),
                      let bookmark = try? BookmarkStore.makeBookmark(for: file) else { continue }
                added.append(PhotoRef(bookmark: bookmark, fileName: file.lastPathComponent,
                                      captureDate: info.captureDate, dateSource: info.dateSource,
                                      aspectRatio: info.aspectRatio))
            }
        }
        guard !added.isEmpty else { return 0 }
        insert(added, undoManager: undoManager)
        undoManager?.setActionName("Bilder hinzufügen")
        return added.count
    }

    @MainActor
    func remove(_ ids: Set<UUID>, undoManager: UndoManager?) {
        let removed = photos.filter { ids.contains($0.id) }
        photos.removeAll { ids.contains($0.id) }
        ids.forEach(bookmarks.forget)
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated { doc.insert(removed, undoManager: undoManager) }
        }
        undoManager?.setActionName("Aus Zeitstrahl entfernen")
    }

    @MainActor
    private func insert(_ refs: [PhotoRef], undoManager: UndoManager?) {
        photos.append(contentsOf: refs)
        let ids = Set(refs.map(\.id))
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated { doc.remove(ids, undoManager: undoManager) }
        }
    }

    /// Writes the new date into the file (EXIF + file dates). Undo writes the old one back.
    @MainActor
    func setCaptureDate(_ date: Date, for id: UUID, undoManager: UndoManager?) throws {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        guard let url = url(for: photos[i]) else { throw CocoaError(.fileNoSuchFile) }
        let old = photos[i].captureDate
        try MetadataWriter.setCaptureDate(date, of: url)
        photos[i].captureDate = date
        photos[i].dateSource = .exif
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated { try? doc.setCaptureDate(old, for: id, undoManager: undoManager) }
        }
        undoManager?.setActionName("Aufnahmedatum ändern")
    }

    nonisolated static func imageFiles(in url: URL) -> [URL] {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard isDir else { return isImage(url) ? [url] : [] }
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        return (enumerator?.allObjects as? [URL] ?? []).filter(isImage).sorted { $0.path < $1.path }
    }

    nonisolated private static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }
}
