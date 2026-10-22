import SwiftUI

/// Enlarged view of up to two photos side by side.
struct PreviewPane: View {
    let photos: [PhotoRef]
    let url: (PhotoRef) -> URL?
    let close: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                if index > 0 { Divider() }
                PreviewImage(photo: photo, url: url(photo)) { close(photo.id) }
            }
        }
        .background(.background.secondary)
    }
}

private struct PreviewImage: View {
    let photo: PhotoRef
    let url: URL?
    let close: () -> Void

    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(photo.fileName).fontWeight(.medium)
                Text(TimelineView.format(photo.captureDate)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Schließen", systemImage: "xmark.circle.fill", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Vorschau schließen")
            }
            .font(.callout)
            .lineLimit(1)

            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 4))
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            guard let url else { return }
            image = await ThumbnailCache.shared.thumbnail(for: url, maxPixelSize: 2400)
        }
    }
}
