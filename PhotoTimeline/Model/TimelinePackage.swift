import Foundation

/// What a `.phototimeline` package holds on disk:
///
///     Urlaub.phototimeline/
///     ├── timeline.json
///     ├── preview.png        ← Quick Look
///     └── Thumbnails/<photo id>.jpg
///
/// Files from before the package format are a single JSON file; they still load and become a package on the next save.
nonisolated struct TimelinePackage: Sendable {
    var file: FileFormat
    /// JPEG thumbnails by photo id, so tiles show without reading the originals.
    var thumbnails: [UUID: Data] = [:]
    /// Image of the whole timeline.
    var preview: Data?

    nonisolated struct FileFormat: Codable, Sendable {
        var version = 1
        var photos: [PhotoRef]
        /// Optional so files from before the setting existed still load.
        var granularity: DateGranularity?
    }

    static let timelineName = "timeline.json"
    static let previewName = "preview.png"
    static let thumbnailsName = "Thumbnails"

    init(file: FileFormat) {
        self.file = file
    }

    init(fileWrapper: FileWrapper) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard fileWrapper.isDirectory else {
            guard let data = fileWrapper.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            file = try decoder.decode(FileFormat.self, from: data)
            return
        }
        let children = fileWrapper.fileWrappers ?? [:]
        guard let data = children[Self.timelineName]?.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        file = try decoder.decode(FileFormat.self, from: data)
        preview = children[Self.previewName]?.regularFileContents
        for (name, child) in children[Self.thumbnailsName]?.fileWrappers ?? [:] {
            if let id = UUID(uuidString: (name as NSString).deletingPathExtension), let data = child.regularFileContents {
                thumbnails[id] = data
            }
        }
    }

    /// Writes thumbnails only for photos still on the timeline; removed ones stay in memory for undo.
    func fileWrapper() throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var children = [Self.timelineName: FileWrapper(regularFileWithContents: try encoder.encode(file))]
        var thumbnailFiles: [String: FileWrapper] = [:]
        for photo in file.photos {
            if let data = thumbnails[photo.id] {
                thumbnailFiles["\(photo.id.uuidString).jpg"] = FileWrapper(regularFileWithContents: data)
            }
        }
        children[Self.thumbnailsName] = FileWrapper(directoryWithFileWrappers: thumbnailFiles)
        if let preview {
            children[Self.previewName] = FileWrapper(regularFileWithContents: preview)
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }
}
