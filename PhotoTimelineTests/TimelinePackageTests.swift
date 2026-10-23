import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PhotoTimeline

struct TimelinePackageTests {
    private func photo(_ name: String) -> PhotoRef {
        PhotoRef(bookmark: Data(), fileName: name, captureDate: Date(timeIntervalSince1970: 1_700_000_000),
                 dateSource: .exif, aspectRatio: 1.5)
    }

    @Test func roundTripKeepsThumbnailsAndPreview() throws {
        let a = photo("a.jpg"), b = photo("b.jpg")
        var package = TimelinePackage(file: .init(photos: [a, b], granularity: .day))
        package.thumbnails = [a.id: Data([1, 2, 3]), b.id: Data([4, 5])]
        package.preview = Data([9, 9])

        let wrapper = try package.fileWrapper()
        #expect(wrapper.isDirectory)
        #expect(Set(try #require(wrapper.fileWrappers).keys) == ["timeline.json", "preview.png", "Thumbnails"])

        let read = try TimelinePackage(fileWrapper: wrapper)
        #expect(read.file.photos.map(\.id) == [a.id, b.id])
        #expect(read.file.granularity == .day)
        #expect(read.thumbnails == package.thumbnails)
        #expect(read.preview == Data([9, 9]))
    }

    @Test func thumbnailsOfRemovedPhotosAreNotWritten() throws {
        let kept = photo("kept.jpg"), removed = photo("removed.jpg")
        var package = TimelinePackage(file: .init(photos: [kept]))
        package.thumbnails = [kept.id: Data([1]), removed.id: Data([2])]

        let thumbnails = try package.fileWrapper().fileWrappers?["Thumbnails"]?.fileWrappers ?? [:]
        #expect(Array(thumbnails.keys) == ["\(kept.id.uuidString).jpg"])
    }

    @Test func readsSingleFileDocumentsFromBeforeThePackageFormat() throws {
        let json = """
        {"version": 1, "granularity": "year", "photos": [{"id": "\(UUID().uuidString)", "bookmark": "",
          "fileName": "a.jpg", "captureDate": "2024-01-01T10:00:00Z", "dateSource": "exif", "aspectRatio": 1.5}]}
        """
        let read = try TimelinePackage(fileWrapper: FileWrapper(regularFileWithContents: Data(json.utf8)))
        #expect(read.file.photos.map(\.fileName) == ["a.jpg"])
        #expect(read.file.granularity == .year)
        #expect(read.thumbnails.isEmpty)
        #expect(read.preview == nil)
    }

    @Test func documentTypeIsAPackage() {
        #expect(UTType.photoTimeline.conforms(to: .package))
        #expect(!UTType.photoTimeline.conforms(to: .json))
    }

    /// A package type only matches folders, so old single files need their own type to open at all.
    @Test func singleFileDocumentsHaveTheirOwnReadOnlyType() {
        #expect(UTType.photoTimelineJSON.conforms(to: .json))
        #expect(UTType.photoTimelineJSON.preferredFilenameExtension == "phototimeline")
        #expect(TimelineDocument.readableContentTypes.contains(.photoTimelineJSON))
        #expect(TimelineDocument.writableContentTypes == [.photoTimeline])
    }
}
