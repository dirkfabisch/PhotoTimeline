import SwiftUI

/// Enlarged view of up to two photos side by side.
struct PreviewPane: View {
    let photos: [PhotoRef]
    let url: (PhotoRef) -> URL?
    let thumbnail: (PhotoRef) -> CGImage?
    let close: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                if index > 0 { Divider() }
                PreviewImage(photo: photo, url: url(photo), thumbnail: thumbnail(photo)) { close(photo.id) }
            }
        }
        .background(.background.secondary)
    }
}

private struct PreviewImage: View {
    let photo: PhotoRef
    let url: URL?
    /// Shown enlarged until the full image is loaded.
    let thumbnail: CGImage?
    let close: () -> Void

    @State private var image: CGImage?
    @State private var showsSpinner = false

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
                if let shown = image ?? thumbnail {
                    Image(decorative: shown, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if showsSpinner {
                    ProgressView()
                        .padding(12)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            guard let url else { return }
            // Only a load that takes noticeably long gets a spinner.
            let spinner = Task {
                try await Task.sleep(for: .milliseconds(300))
                showsSpinner = true
            }
            defer {
                spinner.cancel()
                showsSpinner = false
            }
            image = await ThumbnailCache.shared.thumbnail(for: url, maxPixelSize: 2400)
        }
    }
}
