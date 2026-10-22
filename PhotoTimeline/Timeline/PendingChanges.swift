import SwiftUI

/// Bar above the timeline while dates are changed on the timeline but not in the files.
struct PendingBanner: View {
    let count: Int
    let discard: () -> Void
    let write: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(count == 1
                 ? "1 Datumsänderung ist noch nicht in den Fotos gespeichert"
                 : "\(count) Datumsänderungen sind noch nicht in den Fotos gespeichert")
                .fontWeight(.medium)
            Spacer()
            Button("Verwerfen", action: discard)
            Button("In Fotos schreiben…", action: write)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.15))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Lists every pending change before they are written into the files.
struct WriteConfirmation: View {
    let photos: [PhotoRef]
    let write: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aufnahmedaten in Fotos schreiben?")
                .font(.headline)
            Text("EXIF-Aufnahmedatum und Dateidatum werden in den Originaldateien überschrieben. ⌘Z schreibt die alten Daten zurück.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(photos.sorted { $0.captureDate < $1.captureDate }) { photo in
                HStack {
                    Text(photo.fileName).lineLimit(1)
                    Spacer()
                    Text(TimelineView.format(photo.dateInFile)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(TimelineView.format(photo.captureDate)).fontWeight(.medium)
                }
                .monospacedDigit()
            }
            .frame(minHeight: 120, idealHeight: 260)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(photos.count == 1 ? "1 Foto schreiben" : "\(photos.count) Fotos schreiben") {
                    dismiss()
                    write()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
