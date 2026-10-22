import SwiftUI

struct ContentView: View {
    @ObservedObject var document: TimelineDocument

    @Environment(\.undoManager) private var undoManager
    @SceneStorage("orientation") private var orientation: TimelineOrientation = .horizontal
    /// log10 of points per second.
    @State private var zoom: Double = -4
    @State private var viewport: CGSize = .zero
    @State private var isTargeted = false
    /// Photos shown enlarged, oldest first.
    @State private var previewIDs: [UUID] = []
    @State private var pinchBase: Double?
    @State private var zoomAnchor: CGPoint?
    @State private var tileSize = TimelineLayout.maxTileSize
    /// True until the user zooms; window size changes then refit (e.g. restored frames after opening).
    @State private var isFitted = true
    @State private var confirmWrite = false
    @State private var writeFailures: [String] = []

    private let zoomRange: ClosedRange<Double> = -8...0

    var body: some View {
        // Preview goes below a horizontal timeline and beside a vertical one.
        let stack = orientation == .horizontal ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        let previews = previewIDs.compactMap { id in document.photos.first { $0.id == id } }

        stack {
            timeline
            if !previews.isEmpty {
                Divider()
                PreviewPane(photos: previews, url: document.url(for:)) { togglePreview($0) }
            }
        }
        .animation(.snappy(duration: 0.2), value: previewIDs)
    }

    private var timeline: some View {
        TimelineView(document: document, orientation: orientation, pointsPerSecond: pow(10, zoom), tileSize: tileSize,
                     zoomAnchor: zoomAnchor, selection: previewIDs, onSelect: togglePreview)
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBase ?? zoom
                        pinchBase = base
                        zoomAnchor = value.startLocation
                        setZoom(base + log10(value.magnification))
                    }
                    .onEnded { _ in
                        pinchBase = nil
                        zoomAnchor = nil
                    }
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                let pending = document.photos.filter(\.hasPendingDate).count
                if pending > 0 {
                    PendingBanner(count: pending) {
                        document.discardPendingDates(undoManager: undoManager)
                    } write: {
                        confirmWrite = true
                    }
                }
            }
            .sheet(isPresented: $confirmWrite) {
                WriteConfirmation(photos: document.photos.filter(\.hasPendingDate)) {
                    writeFailures = document.writePendingDates(undoManager: undoManager)
                }
            }
            .alert("Nicht alle Fotos konnten geschrieben werden",
                   isPresented: Binding(get: { !writeFailures.isEmpty }, set: { if !$0 { writeFailures = [] } })) {
                Button("OK") {}
            } message: {
                Text(writeFailures.joined(separator: "\n") + "\n\nDiese Änderungen bleiben offen.")
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { size in
                viewport = size
                if isFitted { fit() }
            }
            .overlay {
                if document.photos.isEmpty {
                    ContentUnavailableView("Bilder hierher ziehen", systemImage: "photo.on.rectangle.angled",
                                           description: Text("Einzelne Bilder oder ganze Ordner. Die Dateien bleiben, wo sie sind."))
                }
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 3).padding(4)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                let wasEmpty = document.photos.isEmpty
                let added = document.add(urls, undoManager: undoManager)
                if wasEmpty, added > 0 { fit() }
                return added > 0
            } isTargeted: { isTargeted = $0 }
            .onAppear {
                #if DEBUG
                // Lets automated runs populate a window without Finder drag & drop.
                if let dir = ProcessInfo.processInfo.environment["PT_DEMO_DIR"], document.photos.isEmpty {
                    document.add([URL(filePath: dir)], undoManager: nil)
                    fit()
                }
                #endif
            }
            .toolbar {
                ToolbarItem {
                    Picker("Ausrichtung", selection: $orientation) {
                        Label("Horizontal", systemImage: "arrow.left.and.right").tag(TimelineOrientation.horizontal)
                        Label("Vertikal", systemImage: "arrow.up.and.down").tag(TimelineOrientation.vertical)
                    }
                    .pickerStyle(.segmented)
                    .help("Ausrichtung des Zeitstrahls")
                }
                ToolbarItem {
                    Picker("Granularität", selection: Binding(
                        get: { document.granularity },
                        set: { document.setGranularity($0, undoManager: undoManager) })) {
                        ForEach(DateGranularity.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .help("Welche Teile des Datums beim Verschieben geändert werden")
                }
                ToolbarItemGroup {
                    Button("Verkleinern", systemImage: "minus.magnifyingglass") { setZoom(zoom - 0.25) }
                        .keyboardShortcut("-")
                    Slider(value: Binding(get: { zoom }, set: setZoom), in: zoomRange)
                        .frame(width: 140)
                        .help("Zoom")
                    Button("Vergrößern", systemImage: "plus.magnifyingglass") { setZoom(zoom + 0.25) }
                        .keyboardShortcut("+")
                    Button("Einpassen", systemImage: "arrow.down.right.and.arrow.up.left") { fit() }
                        .keyboardShortcut("0")
                        .disabled(document.photos.count < 2)
                }
            }
            .onChange(of: orientation) { fit() }
    }

    /// Click toggles a photo's preview; a third one replaces the oldest.
    private func togglePreview(_ id: UUID) {
        if let index = previewIDs.firstIndex(of: id) {
            previewIDs.remove(at: index)
        } else {
            previewIDs.append(id)
            if previewIDs.count > 2 { previewIDs.removeFirst() }
        }
    }

    private func setZoom(_ value: Double) {
        let new = min(max(value, zoomRange.lowerBound), maxZoom)
        // Tiles shrunk by fit() grow back while zooming in.
        if new > zoom { tileSize = min(TimelineLayout.maxTileSize, tileSize * pow(10, new - zoom)) }
        zoom = new
        isFitted = false
    }

    /// Caps total length so a 10-year span can't be zoomed to second precision.
    private var maxZoom: Double {
        guard let span = dateSpan, span > 0 else { return zoomRange.upperBound }
        return min(zoomRange.upperBound, log10(2_000_000 / span))
    }

    private var dateSpan: TimeInterval? {
        let dates = document.photos.map(\.captureDate)
        guard let min = dates.min(), let max = dates.max() else { return nil }
        return max.timeIntervalSince(min)
    }

    private func fit() {
        let items = document.photos.map { TimelineLayout.Item(id: $0.id, date: $0.captureDate) }
        guard viewport != .zero,
              let fit = TimelineLayout.fit(items: items, orientation: orientation, viewport: viewport) else { return }
        zoom = min(max(log10(fit.pointsPerSecond), zoomRange.lowerBound), maxZoom)
        tileSize = fit.tileSize
        isFitted = true
    }
}
