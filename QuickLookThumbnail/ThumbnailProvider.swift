import QuickLookThumbnailing

/// Finder icon for a timeline document: the image of the whole timeline the app stores in the package.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let url = request.fileURL.appending(path: "preview.png")
        guard FileManager.default.fileExists(atPath: url.path) else {
            handler(nil, CocoaError(.fileReadNoSuchFile))
            return
        }
        handler(QLThumbnailReply(imageFileURL: url), nil)
    }
}
