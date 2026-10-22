import Foundation

/// A reference to an image on disk. The image itself is never copied.
nonisolated struct PhotoRef: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var bookmark: Data
    var fileName: String
    /// Date shown on the timeline; may differ from the file until written.
    var captureDate: Date
    var dateSource: DateSource
    var aspectRatio: Double
    /// Date currently stored in the image file; nil means it equals `captureDate`.
    var fileDate: Date?

    var dateInFile: Date { fileDate ?? captureDate }
    /// Moved on the timeline but not yet written into the image file.
    var hasPendingDate: Bool { dateInFile != captureDate }
}
