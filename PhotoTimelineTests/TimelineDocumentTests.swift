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

    @Test func dateChangeStaysPendingUntilWritten() throws {
        let dir = try makeFolder(dates: ["2024:01:01 10:00:00", "2024:01:01 11:00:00"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = TimelineDocument()
        doc.add([dir], undoManager: nil)
        let photo = try #require(doc.photos.first { $0.fileName == "IMG_0.jpg" })
        let file = dir.appendingPathComponent("IMG_0.jpg")
        let original = photo.captureDate
        let moved = original.addingTimeInterval(3600 * 24)
        let undo = UndoManager()
        undo.groupsByEvent = false

        undo.beginUndoGrouping()
        doc.setCaptureDate(moved, for: photo.id, undoManager: undo)
        undo.endUndoGrouping()
        #expect(CaptureDateReader.read(file)?.captureDate == original, "file untouched")
        #expect(doc.photos.filter(\.hasPendingDate).map(\.id) == [photo.id])

        undo.beginUndoGrouping()
        #expect(doc.writePendingDates(undoManager: undo).isEmpty)
        undo.endUndoGrouping()
        #expect(CaptureDateReader.read(file)?.captureDate == moved)
        #expect(!doc.photos.contains { $0.hasPendingDate })

        // Undoing the write restores the file; the change is pending again.
        undo.undo()
        #expect(CaptureDateReader.read(file)?.captureDate == original)
        #expect(doc.photos.first { $0.id == photo.id }?.hasPendingDate == true)

        // Undoing the move brings back the original date, nothing pending.
        undo.undo()
        #expect(doc.photos.first { $0.id == photo.id }?.captureDate == original)
        #expect(!doc.photos.contains { $0.hasPendingDate })
    }

    @Test func discardResetsAllPendingDates() throws {
        let dir = try makeFolder(dates: ["2024:01:01 10:00:00", "2024:01:01 11:00:00"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = TimelineDocument()
        doc.add([dir], undoManager: nil)
        let originals = Dictionary(uniqueKeysWithValues: doc.photos.map { ($0.id, $0.captureDate) })
        for photo in doc.photos {
            doc.setCaptureDate(photo.captureDate.addingTimeInterval(600), for: photo.id, undoManager: nil)
        }
        #expect(doc.photos.allSatisfy { $0.hasPendingDate })

        doc.discardPendingDates(undoManager: nil)
        #expect(doc.photos.allSatisfy { $0.captureDate == originals[$0.id] && !$0.hasPendingDate })
    }

    @Test func failedWriteStaysPending() throws {
        let dir = try makeFolder(dates: ["2024:01:01 10:00:00", "2024:01:01 11:00:00"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = TimelineDocument()
        doc.add([dir], undoManager: nil)
        for photo in doc.photos {
            doc.setCaptureDate(photo.captureDate.addingTimeInterval(600), for: photo.id, undoManager: nil)
        }
        try FileManager.default.removeItem(at: dir.appendingPathComponent("IMG_1.jpg"))

        let failures = doc.writePendingDates(undoManager: nil)
        #expect(failures.count == 1)
        #expect(doc.photos.filter(\.hasPendingDate).map(\.fileName) == ["IMG_1.jpg"])
    }

    @Test func decodesFilesFromBeforePendingDates() throws {
        let json = """
        {"version": 1, "photos": [{"id": "\(UUID().uuidString)", "bookmark": "", "fileName": "a.jpg",
          "captureDate": "2024-01-01T10:00:00Z", "dateSource": "exif", "aspectRatio": 1.5}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(TimelineDocument.FileFormat.self, from: Data(json.utf8))
        #expect(file.granularity == nil)
        #expect(file.photos.first?.hasPendingDate == false)
    }

    /// AppKit autosaves from a background queue — this used to trap.
    @Test func snapshotFromBackgroundThread() async throws {
        let dir = try makeFolder(dates: ["2024:01:01 10:00:00"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = TimelineDocument()
        doc.add([dir], undoManager: nil)
        let count = try await Task.detached { try doc.snapshot(contentType: .photoTimeline).photos.count }.value
        #expect(count == 1)
    }
}
