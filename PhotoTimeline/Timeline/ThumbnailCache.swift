import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decoded images by file and size. Decoding runs off the main actor, several files at once.
nonisolated final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    /// Size of the thumbnails kept in the document: a full-size tile on a Retina display.
    static let tilePixelSize = Int(TimelineLayout.maxTileSize * 2)

    /// NSCache is thread-safe.
    private let cache = NSCache<NSString, CGImage>()

    @concurrent func thumbnail(for url: URL, maxPixelSize: Int) async -> CGImage? {
        let key = "\(url.path)#\(maxPixelSize)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func image(from data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }
}
