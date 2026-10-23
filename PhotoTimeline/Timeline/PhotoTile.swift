import SwiftUI

struct PhotoTile: View {
    let photo: PhotoRef
    /// Stored thumbnail, shown in the first frame.
    let thumbnail: CGImage?
    /// Makes the thumbnail when none is stored yet.
    var load: (() async -> CGImage?)?
    /// The original file can't be found.
    var isMissing = false
    let size: CGFloat
    var isDragging = false
    var isSelected = false

    @State private var loaded: CGImage?

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
            .overlay(alignment: .topLeading) {
                if photo.hasPendingDate {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .orange)
                        .padding(2)
                        .help("Neues Datum noch nicht in die Datei geschrieben")
                }
            }
            .scaleEffect(isDragging ? 1.08 : 1)
            .shadow(color: .black.opacity(isDragging ? 0.3 : 0.18),
                    radius: isDragging ? 18 : 2, y: isDragging ? 14 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.25), value: isDragging)
            .task(id: photo.id) {
                guard thumbnail == nil, let load else { return }
                loaded = await load()
            }
    }

    @ViewBuilder private var content: some View {
        if let image = thumbnail ?? loaded {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .modifier(PrintFrame(isSelected: isSelected))
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: isMissing ? "exclamationmark.triangle" : "photo")
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
