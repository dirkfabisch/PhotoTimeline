import SwiftUI
import Synchronization
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let photoTimeline = UTType(exportedAs: "de.fabisch.phototimeline")
    /// Single JSON file from before the package format; same extension, read only.
    nonisolated static let photoTimelineJSON = UTType(exportedAs: "de.fabisch.phototimeline.json")
}

/// ReferenceFileDocument is Sendable, so the class itself can't be main-actor bound.
/// `photos` is only touched from the main actor (editing API is `@MainActor`).
/// AppKit takes snapshots on a background queue while saving, so those read a
/// lock-protected copy instead.
final class TimelineDocument: ReferenceFileDocument, @unchecked Sendable {
    nonisolated static var readableContentTypes: [UTType] { [.photoTimeline, .photoTimelineJSON] }
    nonisolated static var writableContentTypes: [UTType] { [.photoTimeline] }

    @Published var photos: [PhotoRef] {
        didSet { updateSaved() }
    }
    @Published private(set) var granularity: DateGranularity {
        didSet { updateSaved() }
    }
    /// Also holds the thumbnails and the preview image, which change without an undo step.
    private let saved: Mutex<TimelinePackage>
    let bookmarks = BookmarkStore()
    /// Thumbnails decoded from `saved` or made from the originals.
    @MainActor private var thumbnailImages: [UUID: CGImage] = [:]
    @MainActor private var thumbnailTasks: [UUID: Task<CGImage?, Never>] = [:]

    init() {
        let granularity = DateGranularity.standard
        saved = Mutex(TimelinePackage(file: .init(photos: [], granularity: granularity)))
        photos = []
        self.granularity = granularity
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        var package = try TimelinePackage(fileWrapper: configuration.file)
        package.file.granularity = package.file.granularity ?? DateGranularity.standard
        saved = Mutex(package)
        _photos = Published(initialValue: package.file.photos)
        _granularity = Published(initialValue: package.file.granularity ?? .all)
    }

    nonisolated func snapshot(contentType: UTType) throws -> TimelinePackage {
        saved.withLock { $0 }
    }

    nonisolated func fileWrapper(snapshot: TimelinePackage, configuration: WriteConfiguration) throws -> FileWrapper {
        try snapshot.fileWrapper()
    }

    private func updateSaved() {
        saved.withLock { [photos, granularity] in $0.file = .init(photos: photos, granularity: granularity) }
    }

    // MARK: Thumbnails and preview

    /// The stored thumbnail, if there is one. Synchronous, so tiles show it in their first frame.
    @MainActor
    func thumbnail(for id: UUID) -> CGImage? {
        if let image = thumbnailImages[id] { return image }
        guard let data = saved.withLock({ $0.thumbnails[id] }),
              let image = ThumbnailCache.image(from: data) else { return nil }
        thumbnailImages[id] = image
        return image
    }

    /// The stored thumbnail, or a new one made from the original and kept in the document.
    @MainActor
    func loadThumbnail(for photo: PhotoRef) async -> CGImage? {
        if let image = thumbnail(for: photo.id) { return image }
        if let task = thumbnailTasks[photo.id] { return await task.value }
        guard let url = url(for: photo) else { return nil }
        let task = Task { await ThumbnailCache.shared.thumbnail(for: url, maxPixelSize: ThumbnailCache.tilePixelSize) }
        thumbnailTasks[photo.id] = task
        let image = await task.value
        thumbnailTasks[photo.id] = nil
        if let image, let data = ThumbnailCache.jpegData(image) {
            thumbnailImages[photo.id] = image
            saved.withLock { $0.thumbnails[photo.id] = data }
        }
        return image
    }

    /// Renders the image Quick Look and the Finder show, once every photo has a thumbnail.
    @MainActor
    func updatePreview(orientation: TimelineOrientation) async {
        await withTaskGroup { group in
            for photo in photos where thumbnail(for: photo.id) == nil {
                group.addTask { _ = await self.loadThumbnail(for: photo) }
            }
        }
        guard !Task.isCancelled else { return }
        let preview = TimelinePreview.render(photos: photos, orientation: orientation, thumbnail: thumbnail(for:))
        saved.withLock { $0.preview = preview }
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
        undoManager?.setActionName(String(localized: "Bilder hinzufügen"))
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
        undoManager?.setActionName(String(localized: "Aus Zeitstrahl entfernen"))
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
        undoManager?.setActionName(String(localized: "Granularität ändern"))
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
        undoManager?.setActionName(String(localized: "Aufnahmedatum ändern"))
    }

    /// Resets every pending date to what the file holds.
    @MainActor
    func discardPendingDates(undoManager: UndoManager?) {
        for photo in photos where photo.hasPendingDate {
            setCaptureDate(photo.dateInFile, for: photo.id, undoManager: undoManager)
        }
        undoManager?.setActionName(String(localized: "Änderungen verwerfen"))
    }

    /// Writes all pending dates into the image files (EXIF + file dates) in one go.
    /// Undo writes the previous dates back. Returns a message per file that failed; those stay pending.
    @MainActor
    func writePendingDates(undoManager: UndoManager?) -> [String] {
        let dates = photos.filter(\.hasPendingDate).map { ($0.id, $0.captureDate) }
        let failures = writeFileDates(dates, undoManager: undoManager)
        undoManager?.setActionName(String(localized: "In Fotos schreiben"))
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
