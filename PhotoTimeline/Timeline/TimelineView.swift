import SwiftUI

struct TimelineView: View {
    @ObservedObject var document: TimelineDocument
    let orientation: TimelineOrientation
    let pointsPerSecond: Double
    var tileSize: CGFloat = TimelineLayout.maxTileSize
    /// Point in the view that stays fixed while zooming (pinch location); nil = center.
    var zoomAnchor: CGPoint?
    var selection: [UUID] = []
    var onSelect: (UUID) -> Void = { _ in }

    @Environment(\.undoManager) private var undoManager
    @State private var visibleRect: CGRect = .zero
    @State private var containerSize: CGSize = .zero
    @State private var scrollPosition = ScrollPosition()
    @State private var drag: DragState?

    private struct DragState: Equatable {
        var id: UUID
        var offset: CGFloat
    }

    var body: some View {
        let layout = TimelineLayout(
            items: document.photos.map { .init(id: $0.id, date: $0.captureDate) },
            orientation: orientation, pointsPerSecond: pointsPerSecond, tileSize: tileSize)
        // Center the timeline when it is smaller than the window.
        let pad = CGSize(width: max(0, (containerSize.width - layout.contentSize.width) / 2),
                         height: max(0, (containerSize.height - layout.contentSize.height) / 2))
        let drawRect = drawRect(for: layout, pad: pad)
        let photos = Dictionary(uniqueKeysWithValues: document.photos.map { ($0.id, $0) })
        let visible = layout.placements.filter {
            layout.alongRange(of: drawRect).contains(displayedAlong(of: $0))
        }
        let pendingIDs = Set(document.photos.filter(\.hasPendingDate).map(\.id))

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                AxisCanvas(layout: layout, rect: drawRect, placements: visible, pending: pendingIDs,
                           drag: drag.map { ($0.id, $0.offset) })
                    .frame(width: drawRect.width, height: drawRect.height)
                    .offset(x: drawRect.minX, y: drawRect.minY)
                    .allowsHitTesting(false)

                ForEach(visible) { placement in
                    if let photo = photos[placement.id] {
                        tile(photo, placement, layout)
                    }
                }
            }
            .frame(width: layout.contentSize.width, height: layout.contentSize.height, alignment: .topLeading)
            .padding(.horizontal, pad.width)
            .padding(.vertical, pad.height)
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGRect.self, of: \.visibleRect) { _, rect in
            visibleRect = rect
        }
        .onScrollGeometryChange(for: CGSize.self, of: \.containerSize) { _, size in
            let first = containerSize == .zero
            containerSize = size
            if first { scrollToStart(layout: layout) }
        }
        .onChange(of: pointsPerSecond) { old, new in
            keepCenterDate(layout: layout, oldPPS: old, newPPS: new)
        }
        .onChange(of: orientation) { scrollToStart(layout: layout) }
        .onChange(of: document.photos.isEmpty) { scrollToStart(layout: layout) }
    }

    // MARK: Tiles

    private func displayedAlong(of placement: TimelineLayout.Placement) -> CGFloat {
        placement.along + (drag?.id == placement.id ? drag!.offset : 0)
    }

    private func tile(_ photo: PhotoRef, _ placement: TimelineLayout.Placement, _ layout: TimelineLayout) -> some View {
        let isDragging = drag?.id == photo.id
        let along = displayedAlong(of: placement)
        let url = document.url(for: photo)

        return PhotoTile(photo: photo, url: url, size: layout.tileSize, isDragging: isDragging,
                         isSelected: selection.contains(photo.id))
            .overlay(alignment: .bottom) {
                if isDragging {
                    Text(Self.format(newDate(for: photo, atAlong: along, layout: layout)))
                        .font(.system(.title3, design: .serif, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.accentColor, in: Capsule())
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        .fixedSize()
                        .offset(y: 40)
                }
            }
            .help(photo.hasPendingDate
                  ? String(localized: "\(photo.fileName)\n\(Self.format(photo.captureDate))\nIn der Datei noch: \(Self.format(photo.dateInFile))")
                  : "\(photo.fileName)\n\(Self.format(photo.captureDate))")
            .position(layout.point(along: along, cross: placement.cross))
            .zIndex(isDragging ? 1 : 0)
            .onTapGesture { onSelect(photo.id) }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        drag = DragState(id: photo.id, offset: layout.alongComponent(of: value.translation))
                    }
                    .onEnded { value in
                        let date = newDate(for: photo, atAlong: placement.along + layout.alongComponent(of: value.translation),
                                           layout: layout)
                        drag = nil
                        document.setCaptureDate(date, for: photo.id, undoManager: undoManager)
                    }
            )
            .contextMenu {
                if let url {
                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Button("Aus Zeitstrahl entfernen", role: .destructive) {
                    document.remove([photo.id], undoManager: undoManager)
                }
            }
    }

    /// Date a drag to `along` results in, limited to the document's granularity.
    private func newDate(for photo: PhotoRef, atAlong along: CGFloat, layout: TimelineLayout) -> Date {
        document.granularity.apply(layout.date(atAlong: along), to: photo.captureDate)
    }

    // MARK: Scrolling

    /// Only the visible slice (plus a buffer) is rendered; the timeline can be very long.
    private func drawRect(for layout: TimelineLayout, pad: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: layout.contentSize)
        let base = visibleRect.isEmpty
            ? CGRect(x: 0, y: 0, width: 3000, height: 3000)
            : visibleRect.offsetBy(dx: -pad.width, dy: -pad.height)
        let buffer = layout.tileSize * 2
        return base.insetBy(dx: -buffer, dy: -buffer).intersection(bounds)
    }

    /// Start of the timeline, with the axis in the middle of the window.
    private func scrollToStart(layout: TimelineLayout) {
        let horizontal = orientation == .horizontal
        let viewport = horizontal ? containerSize.height : containerSize.width
        let cross = max(0, layout.crossExtentPerSide - viewport / 2)
        scrollPosition.scrollTo(point: horizontal ? CGPoint(x: 0, y: cross) : CGPoint(x: cross, y: 0))
    }

    /// Keeps the date under the zoom anchor (default: window center) in place while zooming.
    private func keepCenterDate(layout: TimelineLayout, oldPPS: Double, newPPS: Double) {
        guard !visibleRect.isEmpty, oldPPS > 0 else { return }
        let horizontal = orientation == .horizontal
        let viewport = horizontal ? visibleRect.width : visibleRect.height
        let anchor = zoomAnchor.map { horizontal ? $0.x : $0.y } ?? viewport / 2
        let pivot = (horizontal ? visibleRect.minX : visibleRect.minY) + anchor - layout.margin
        let newPivot = layout.margin + pivot * CGFloat(newPPS / oldPPS)
        let start = max(0, newPivot - anchor)
        scrollPosition.scrollTo(point: horizontal
            ? CGPoint(x: start, y: visibleRect.minY)
            : CGPoint(x: visibleRect.minX, y: start))
    }

    // MARK: Formatting

    static func format(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.twoDigits).year().hour().minute())
    }
}

/// Axis line, ticks, exact-time dots and connectors for the visible slice.
private struct AxisCanvas: View {
    let layout: TimelineLayout
    let rect: CGRect
    let placements: [TimelineLayout.Placement]
    /// Photos whose date isn't written to the file yet.
    let pending: Set<UUID>
    let drag: (UUID, CGFloat)?

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: -rect.minX, y: -rect.minY)
            let range = layout.alongRange(of: rect)
            let horizontal = layout.orientation == .horizontal

            var axis = Path()
            axis.move(to: layout.point(along: range.lowerBound, cross: 0))
            axis.addLine(to: layout.point(along: range.upperBound, cross: 0))
            context.stroke(axis, with: .color(.primary), lineWidth: 3)

            let ticks = AxisTicks.ticks(from: layout.date(atAlong: range.lowerBound),
                                        to: layout.date(atAlong: range.upperBound),
                                        pointsPerSecond: layout.pointsPerSecond)
            for tick in ticks {
                let along = layout.along(for: tick.date)
                var mark = Path()
                mark.move(to: layout.point(along: along, cross: -7))
                mark.addLine(to: layout.point(along: along, cross: 7))
                context.stroke(mark, with: .color(.primary), lineWidth: 1.5)
                let label = context.resolve(Text(tick.label)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary))
                // Labels sit in the gap between axis and first lane.
                let anchor = layout.point(along: along, cross: horizontal ? 17 : 10)
                context.draw(label, at: anchor, anchor: horizontal ? .center : .leading)
            }

            for placement in placements {
                let isDragged = drag?.0 == placement.id
                let along = placement.along + (isDragged ? drag!.1 : 0)
                let tileEdge = placement.cross - (placement.cross < 0 ? -1 : 1) * layout.tileSize / 2
                var connector = Path()
                connector.move(to: layout.point(along: along, cross: 0))
                connector.addLine(to: layout.point(along: along, cross: tileEdge))
                let color: Color = isDragged ? .accentColor : pending.contains(placement.id) ? .orange : .secondary.opacity(0.5)
                context.stroke(connector, with: .color(color), lineWidth: isDragged ? 1.5 : 1)

                let dot = layout.point(along: along, cross: 0)
                let r: CGFloat = isDragged ? 4 : 3
                context.fill(Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(isDragged ? .accentColor : pending.contains(placement.id) ? .orange : .primary))
            }
        }
    }
}
