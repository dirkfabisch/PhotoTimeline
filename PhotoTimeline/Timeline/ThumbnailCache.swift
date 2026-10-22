import Foundation
import ImageIO

actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, CGImage>()

    func thumbnail(for url: URL, maxPixelSize: Int) -> CGImage? {
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
}
