import Foundation
import ImageIO

nonisolated enum DateSource: String, Codable, Sendable {
    case exif
    case file
}

nonisolated struct ImageInfo: Sendable {
    var captureDate: Date
    var dateSource: DateSource
    /// width / height, already corrected for EXIF orientation.
    var aspectRatio: Double
}

nonisolated enum CaptureDateReader {
    static func read(_ url: URL) -> ImageInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let aspect = aspectRatio(props)
        if let date = exifDate(props) {
            return ImageInfo(captureDate: date, dateSource: .exif, aspectRatio: aspect)
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let fileDate = values?.creationDate ?? values?.contentModificationDate ?? Date()
        return ImageInfo(captureDate: fileDate, dateSource: .file, aspectRatio: aspect)
    }

    /// Time zone recorded in the file, if any.
    static func recordedTimeZone(_ props: [CFString: Any]) -> TimeZone? {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifOffsetTime] as? String
        return offset.flatMap(ExifDateFormat.timeZone(fromOffset:))
    }

    static func exifDate(_ props: [CFString: Any]) -> Date? {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifOffsetTime] as? String
        let raw = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        return raw.flatMap { ExifDateFormat.date(from: $0, offset: offset) }
    }

    private static func aspectRatio(_ props: [CFString: Any]) -> Double {
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 1
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 1
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        guard w > 0, h > 0 else { return 1 }
        // Orientations 5–8 are rotated by 90°.
        return orientation >= 5 ? h / w : w / h
    }
}
