import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum MetadataWriterError: LocalizedError {
    case unreadable
    case unsupportedFormat(String)
    case writeFailed(String)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: "Die Bilddatei konnte nicht gelesen werden."
        case .unsupportedFormat(let type): "Das Format \(type) kann (noch) nicht beschrieben werden."
        case .writeFailed(let reason): "Schreiben der Metadaten fehlgeschlagen: \(reason)"
        case .verificationFailed: "Die geschriebenen Metadaten konnten nicht verifiziert werden. Die Datei wurde nicht verändert."
        }
    }
}

/// Rewrites the capture date of an image in place, without re-encoding pixels.
nonisolated enum MetadataWriter {
    static func setCaptureDate(_ date: Date, of url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw MetadataWriterError.unreadable }

        // Keep the time zone the photo was taken in; fall back to local time.
        let timeZone = CaptureDateReader.recordedTimeZone(props) ?? .current
        let exifString = ExifDateFormat.string(from: date, in: timeZone)
        let offset = ExifDateFormat.offsetString(for: timeZone, at: date)

        let data = NSMutableData()
        let count = CGImageSourceGetCount(source)
        guard let destination = CGImageDestinationCreateWithData(data, type, count, nil) else {
            throw MetadataWriterError.unsupportedFormat(type as String)
        }

        // ImageIO only updates EXIF in place for some formats; each path below was
        // checked per format (see MetadataWriterTests).
        let ok: Bool
        var error: Unmanaged<CFError>?
        switch type as String {
        case UTType.png.identifier, UTType.tiff.identifier:
            // Lossless formats: re-encoding keeps pixels identical.
            let exif: [CFString: Any] = [
                kCGImagePropertyExifDateTimeOriginal: exifString,
                kCGImagePropertyExifDateTimeDigitized: exifString,
                kCGImagePropertyExifOffsetTimeOriginal: offset,
                kCGImagePropertyExifOffsetTimeDigitized: offset,
                kCGImagePropertyExifOffsetTime: offset,
            ]
            let changes: [CFString: Any] = [
                kCGImagePropertyExifDictionary: exif,
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: exifString],
            ]
            for index in 0..<count {
                CGImageDestinationAddImageFromSource(destination, source, index, index == 0 ? changes as CFDictionary : nil)
            }
            ok = CGImageDestinationFinalize(destination)
        case UTType.jpeg.identifier:
            let options: [CFString: Any] = [
                kCGImageDestinationMetadata: jpegMetadata(date: date, exifString: exifString, offset: offset,
                                                          timeZone: timeZone, source: source),
                kCGImageDestinationMergeMetadata: true,
            ]
            ok = CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error)
        default:
            // HEIC and others: lossless copy with ImageIO's own date rewrite (all EXIF/TIFF dates).
            // Can't be combined with kCGImageDestinationMetadata; the offset stays as recorded.
            let options = [kCGImageDestinationDateTime: exifString] as CFDictionary
            ok = CGImageDestinationCopyImageSource(destination, source, options, &error)
        }
        guard ok else {
            let reason = error?.takeRetainedValue().localizedDescription
            throw reason.map(MetadataWriterError.writeFailed) ?? .unsupportedFormat(type as String)
        }

        // Read the result back before touching the original.
        guard let check = CGImageSourceCreateWithData(data, nil),
              let checkProps = CGImageSourceCopyPropertiesAtIndex(check, 0, nil) as? [CFString: Any],
              let written = CaptureDateReader.exifDate(checkProps),
              abs(written.timeIntervalSince(date)) < 1
        else { throw MetadataWriterError.verificationFailed }

        // Sandbox: we only hold access to the file itself, not its folder,
        // so an atomic write (temp file + rename) is not possible.
        do {
            try (data as Data).write(to: url)
        } catch {
            throw MetadataWriterError.writeFailed(error.localizedDescription)
        }

        var values = URLResourceValues()
        values.creationDate = date
        values.contentModificationDate = date
        var fileURL = url
        try fileURL.setResourceValues(values)
    }

    private static func jpegMetadata(date: Date, exifString: String, offset: String,
                                     timeZone: TimeZone, source: CGImageSource) -> CGImageMetadata {
        let metadata = CGImageMetadataCreateMutable()
        let exif = kCGImagePropertyExifDictionary
        CGImageMetadataSetValueMatchingImageProperty(metadata, exif, kCGImagePropertyExifDateTimeOriginal, exifString as CFString)
        CGImageMetadataSetValueMatchingImageProperty(metadata, exif, kCGImagePropertyExifDateTimeDigitized, exifString as CFString)
        CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFDateTime, exifString as CFString)
        CGImageMetadataSetValueMatchingImageProperty(metadata, exif, kCGImagePropertyExifOffsetTimeOriginal, offset as CFString)
        CGImageMetadataSetValueMatchingImageProperty(metadata, exif, kCGImagePropertyExifOffsetTimeDigitized, offset as CFString)
        CGImageMetadataSetValueMatchingImageProperty(metadata, exif, kCGImagePropertyExifOffsetTime, offset as CFString)

        // XMP dates take precedence in many apps — update them if the file has them.
        if let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            let xmp = ExifDateFormat.xmpString(from: date, in: timeZone)
            for path in ["xmp:CreateDate", "photoshop:DateCreated"]
            where CGImageMetadataCopyTagWithPath(existing, nil, path as CFString) != nil {
                CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, xmp as CFString)
            }
        }
        return metadata
    }
}
