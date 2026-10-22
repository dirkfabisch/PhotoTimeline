import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PhotoTimeline

struct TimelineDocumentTests {
    private func makeFolder(dates: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctx = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        for (i, date) in dates.enumerated() {
            let url = dir.appendingPathComponent("IMG_\(i).jpg")
            let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
            let exif = [kCGImagePropertyExifDateTimeOriginal: date, kCGImagePropertyExifOffsetTimeOriginal: "+02:00"]
            CGImageDestinationAddImage(dest, image, [kCGImagePropertyExifDictionary: exif] as CFDictionary)
            #expect(CGImageDestinationFinalize(dest))
        }
        try "no image".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func addsFolderOnceAndUndoes() throws {
        let dir = try makeFolder(dates: ["2024:01:01 10:00:00", "2024:01:01 10:01:00"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = TimelineDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false

        undo.beginUndoGrouping()
        #expect(doc.add([dir], undoManager: undo) == 2)
        undo.endUndoGrouping()
        #expect(doc.add([dir], undoManager: undo) == 0, "duplicates are ignored")

        undo.undo()
        #expect(doc.photos.isEmpty)
    }

    @Test func dateChangeUndoRestoresFile() throws {
        let dir = try makeFolder(dates: ["2024:01:01 10:00:00"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = TimelineDocument()
        doc.add([dir], undoManager: nil)
        let photo = try #require(doc.photos.first)
        let file = dir.appendingPathComponent("IMG_0.jpg")
        let original = photo.captureDate
        let undo = UndoManager()
        undo.groupsByEvent = false

        undo.beginUndoGrouping()
        try doc.setCaptureDate(original.addingTimeInterval(3600), for: photo.id, undoManager: undo)
        undo.endUndoGrouping()
        #expect(CaptureDateReader.read(file)?.captureDate == original.addingTimeInterval(3600))

        undo.undo()
        #expect(CaptureDateReader.read(file)?.captureDate == original)
        #expect(doc.photos.first?.captureDate == original)

        undo.redo()
        #expect(CaptureDateReader.read(file)?.captureDate == original.addingTimeInterval(3600))
    }

    /// AppKit autosaves from a background queue — this used to trap.
    @Test func snapshotFromBackgroundThread() async throws {
        let dir = try makeFolder(dates: ["2024:01:01 10:00:00"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = TimelineDocument()
        doc.add([dir], undoManager: nil)
        let count = try await Task.detached { try doc.snapshot(contentType: .photoTimeline).count }.value
        #expect(count == 1)
    }
}
