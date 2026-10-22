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
        didSet { updateSaved() }
    }
    @Published private(set) var granularity: DateGranularity {
        didSet { updateSaved() }
    }
    private let saved: Mutex<FileFormat>
    let bookmarks = BookmarkStore()

    init() {
        let granularity = DateGranularity.standard
        saved = Mutex(FileFormat(photos: [], granularity: granularity))
        photos = []
        self.granularity = granularity
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var file = try decoder.decode(FileFormat.self, from: data)
        file.granularity = file.granularity ?? DateGranularity.standard
        saved = Mutex(file)
        _photos = Published(initialValue: file.photos)
        _granularity = Published(initialValue: file.granularity ?? .all)
    }

    nonisolated func snapshot(contentType: UTType) throws -> FileFormat {
        saved.withLock { $0 }
    }

    nonisolated func fileWrapper(snapshot: FileFormat, configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return FileWrapper(regularFileWithContents: try encoder.encode(snapshot))
    }

    nonisolated struct FileFormat: Codable, Sendable {
        var version = 1
        var photos: [PhotoRef]
        /// Optional so files from before the setting existed still load.
        var granularity: DateGranularity?
    }

    private func updateSaved() {
        saved.withLock { [photos, granularity] in $0 = FileFormat(photos: photos, granularity: granularity) }
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

    @MainActor
    func setGranularity(_ value: DateGranularity, undoManager: UndoManager?) {
        let old = granularity
        guard value != old else { return }
        granularity = value
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated { doc.setGranularity(old, undoManager: undoManager) }
        }
        undoManager?.setActionName("Granularität ändern")
    }

    /// Changes the date on the timeline only; the image file is untouched until `writePendingDates`.
    @MainActor
    func setCaptureDate(_ date: Date, for id: UUID, undoManager: UndoManager?) {
        guard let i = photos.firstIndex(where: { $0.id == id }), photos[i].captureDate != date else { return }
        var photo = photos[i]
        let old = photo.captureDate
        photo.fileDate = photo.dateInFile
        photo.captureDate = date
        photos[i] = photo
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated { doc.setCaptureDate(old, for: id, undoManager: undoManager) }
        }
        undoManager?.setActionName("Aufnahmedatum ändern")
    }

    /// Resets every pending date to what the file holds.
    @MainActor
    func discardPendingDates(undoManager: UndoManager?) {
        for photo in photos where photo.hasPendingDate {
            setCaptureDate(photo.dateInFile, for: photo.id, undoManager: undoManager)
        }
        undoManager?.setActionName("Änderungen verwerfen")
    }

    /// Writes all pending dates into the image files (EXIF + file dates) in one go.
    /// Undo writes the previous dates back. Returns a message per file that failed; those stay pending.
    @MainActor
    func writePendingDates(undoManager: UndoManager?) -> [String] {
        let dates = photos.filter(\.hasPendingDate).map { ($0.id, $0.captureDate) }
        let failures = writeFileDates(dates, undoManager: undoManager)
        undoManager?.setActionName("In Fotos schreiben")
        return failures
    }

    @MainActor
    private func writeFileDates(_ dates: [(UUID, Date)], undoManager: UndoManager?) -> [String] {
        var previous: [(UUID, Date)] = []
        var failures: [String] = []
        for (id, date) in dates {
            guard let i = photos.firstIndex(where: { $0.id == id }) else { continue }
            let photo = photos[i]
            do {
                guard let url = url(for: photo) else { throw CocoaError(.fileNoSuchFile) }
                try MetadataWriter.setCaptureDate(date, of: url)
                previous.append((id, photo.dateInFile))
                photos[i].fileDate = date
                photos[i].dateSource = .exif
            } catch {
                failures.append("\(photo.fileName): \(error.localizedDescription)")
            }
        }
        if !previous.isEmpty {
            undoManager?.registerUndo(withTarget: self) { doc in
                MainActor.assumeIsolated { _ = doc.writeFileDates(previous, undoManager: undoManager) }
            }
        }
        return failures
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
