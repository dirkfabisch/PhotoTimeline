import SwiftUI

struct PhotoTile: View {
    let photo: PhotoRef
    let url: URL?
    let size: CGFloat
    var isDragging = false
    var isSelected = false

    @State private var image: CGImage?

    var body: some View {
        content
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if photo.dateSource == .file {
                    Image(systemName: "clock.badge.questionmark")
                        .padding(4)
                        .background(.thinMaterial, in: Circle())
                        .padding(4)
                        .help("Kein EXIF-Aufnahmedatum – Dateidatum verwendet")
                }
            }
            // Lifted while dragged: larger, with a soft shadow falling further away.
            .scaleEffect(isDragging ? 1.08 : 1)
            .shadow(color: .black.opacity(isDragging ? 0.3 : 0.18),
                    radius: isDragging ? 18 : 2, y: isDragging ? 14 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.25), value: isDragging)
            .task(id: url) {
                guard let url else { return }
                image = await ThumbnailCache.shared.thumbnail(for: url, maxPixelSize: Int(TimelineLayout.maxTileSize * 2))
            }
    }

    @ViewBuilder private var content: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .modifier(PrintFrame(isSelected: isSelected))
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: url == nil ? "exclamationmark.triangle" : "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(photo.aspectRatio, contentMode: .fit)
                .modifier(PrintFrame(isSelected: isSelected))
        }
    }
}

/// White paper border, like a photo print.
private struct PrintFrame: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .padding(5)
            .background(Color.white, in: .rect(cornerRadius: 2))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.black.opacity(0.12)),
                                  lineWidth: isSelected ? 3 : 0.5)
            }
    }
}
