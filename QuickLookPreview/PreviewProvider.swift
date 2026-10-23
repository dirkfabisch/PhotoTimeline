import QuickLookUI

/// Quick Look for a timeline document: the image of the whole timeline the app stores in the package.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL.appending(path: "preview.png")
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileReadNoSuchFile) }
        return QLPreviewReply(fileURL: url)
    }
}
