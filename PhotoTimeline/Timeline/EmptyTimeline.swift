import SwiftUI

/// Shown instead of the timeline while a document has no photos: a drop zone plus a button.
struct EmptyTimeline: View {
    let isTargeted: Bool
    let choose: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .scaleEffect(isTargeted ? 1.1 : 1)

            VStack(spacing: 10) {
                Text("Fotos hierher ziehen")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                Text("Einzelne Fotos oder ganze Ordner aus dem Finder.\nDie Dateien bleiben, wo sie sind – die Timeline merkt sich nur, wo sie liegen.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button("Fotos auswählen…", systemImage: "folder", action: choose)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        }
        .padding(48)
        .frame(maxWidth: 720, minHeight: 420)
        .background(isTargeted ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.background.secondary),
                    in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary),
                              style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: [10, 6]))
        }
        .animation(.snappy(duration: 0.2), value: isTargeted)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
