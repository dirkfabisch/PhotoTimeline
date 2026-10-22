import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PhotoTimeline

struct MetadataWriterTests {
    private static let original = "2020:01:02 03:04:05"

    /// Writes a small gradient image with an EXIF capture date into a temp file.
    private func makeImage(_ type: UTType, offset: String? = "+01:00") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(type.preferredFilenameExtension ?? "img")
        let ctx = try #require(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in 0..<64 {
            ctx.setFillColor(red: CGFloat(x) / 64, green: 0.5, blue: 1 - CGFloat(x) / 64, alpha: 1)
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: 48))
        }
        let image = try #require(ctx.makeImage())
        var exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: Self.original]
        if let offset { exif[kCGImagePropertyExifOffsetTimeOriginal] = offset }
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyExifDictionary: exif] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func pixels(_ url: URL) throws -> Data {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try #require(image.dataProvider?.data as Data?)
    }

    private func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test(arguments: [UTType.jpeg, .heic, .png, .tiff])
    func writesDateWithoutTouchingPixels(type: UTType) throws {
        let url = try makeImage(type)
        defer { try? FileManager.default.removeItem(at: url) }
        let pixelsBefore = try pixels(url)
        let newDate = try #require(ExifDateFormat.date(from: "2023:07:08 09:10:00", offset: "+01:00"))

        try MetadataWriter.setCaptureDate(newDate, of: url)

        let props = try properties(url)
        let exif = try #require(props[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2023:07:08 09:10:00")
        #expect(exif[kCGImagePropertyExifOffsetTimeOriginal] as? String == "+01:00")
        #expect(CaptureDateReader.exifDate(props) == newDate)
        #expect(try pixels(url) == pixelsBefore)

        let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        #expect(values.contentModificationDate == newDate)
        #expect(values.creationDate == newDate)
    }

    @Test func usesLocalTimeZoneWithoutOffset() throws {
        let url = try makeImage(.jpeg, offset: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let newDate = Date(timeIntervalSince1970: 1_700_000_040)

        try MetadataWriter.setCaptureDate(newDate, of: url)

        let info = try #require(CaptureDateReader.read(url))
        #expect(info.dateSource == .exif)
        #expect(info.captureDate == newDate)
    }

    @Test func readerFallsBackToFileDate() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = try #require(CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))

        let info = try #require(CaptureDateReader.read(url))
        #expect(info.dateSource == .file)
        #expect(info.aspectRatio == 2)
    }
}
