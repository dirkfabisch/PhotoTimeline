import Foundation

/// A reference to an image on disk. The image itself is never copied.
nonisolated struct PhotoRef: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var bookmark: Data
    var fileName: String
    var captureDate: Date
    var dateSource: DateSource
    var aspectRatio: Double
}
