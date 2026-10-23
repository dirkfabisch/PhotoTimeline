import SwiftUI

/// The whole timeline fitted into one image, for Quick Look and the Finder icon.
struct TimelinePreview: View {
    let photos: [PhotoRef]
    let orientation: TimelineOrientation
    let thumbnail: (UUID) -> CGImage?

    /// Points; rendered at 2× so the 240 px thumbnails stay sharp.
    static func size(for orientation: TimelineOrientation) -> CGSize {
        orientation == .horizontal ? CGSize(width: 1000, height: 625) : CGSize(width: 625, height: 1000)
    }

    /// PNG data, or nil for an empty timeline.
    static func render(photos: [PhotoRef], orientation: TimelineOrientation, thumbnail: @escaping (UUID) -> CGImage?) -> Data? {
        guard !photos.isEmpty else { return nil }
        let renderer = ImageRenderer(content: TimelinePreview(photos: photos, orientation: orientation, thumbnail: thumbnail))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    var body: some View {
        let size = Self.size(for: orientation)
        let items = photos.map { TimelineLayout.Item(id: $0.id, date: $0.captureDate) }
        let fit = TimelineLayout.fit(items: items, orientation: orientation, viewport: size)
        let layout = TimelineLayout(items: items, orientation: orientation, pointsPerSecond: fit?.pointsPerSecond ?? 1,
                                    tileSize: fit?.tileSize ?? TimelineLayout.maxTileSize)
        let content = CGRect(origin: .zero, size: layout.contentSize)
        let byID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })

        ZStack(alignment: .topLeading) {
            AxisCanvas(layout: layout, rect: content, placements: layout.placements,
                       pending: Set(photos.filter(\.hasPendingDate).map(\.id)), drag: nil)
            ForEach(layout.placements) { placement in
                if let photo = byID[placement.id] {
                    PhotoTile(photo: photo, thumbnail: thumbnail(photo.id), size: layout.tileSize)
                        .position(layout.point(along: placement.along, cross: placement.cross))
                }
            }
        }
        .frame(width: content.width, height: content.height, alignment: .topLeading)
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
    }
}
