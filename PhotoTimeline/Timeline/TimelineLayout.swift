import CoreGraphics
import Foundation

nonisolated enum TimelineOrientation: String, CaseIterable, Identifiable, Sendable {
    case horizontal, vertical
    var id: Self { self }
}

/// Pure geometry of the timeline. Works in "axis space": `along` follows time,
/// `cross` is perpendicular with the axis at `cross == 0`. Orientation only
/// decides how that maps onto x/y.
nonisolated struct TimelineLayout: Sendable {
    struct Item: Sendable {
        var id: UUID
        var date: Date
    }

    struct Placement: Sendable, Identifiable {
        var id: UUID
        /// Exact point in time on the axis.
        var along: CGFloat
        var lane: Int
        /// Center of the tile, perpendicular to the axis (negative = before/above).
        var cross: CGFloat
    }

    var orientation: TimelineOrientation
    var pointsPerSecond: Double
    var tileSize: CGFloat
    var gap: CGFloat = 8
    /// Space between axis and the first lane, room for connector lines.
    var axisGap: CGFloat = 28

    private(set) var startDate = Date()
    private(set) var placements: [Placement] = []
    private(set) var laneCount = 0
    private(set) var duration: TimeInterval = 0

    var margin: CGFloat { tileSize }

    static let maxTileSize: CGFloat = 120
    static let minTileSize: CGFloat = 48

    init(items: [Item], orientation: TimelineOrientation, pointsPerSecond: Double,
         tileSize: CGFloat = maxTileSize) {
        self.orientation = orientation
        self.pointsPerSecond = pointsPerSecond
        self.tileSize = tileSize
        layout(items)
    }

    /// Zoom and tile size that show the whole timeline in `viewport`: the full time span
    /// along the axis and, shrinking tiles if needed, all lanes across it.
    static func fit(items: [Item], orientation: TimelineOrientation,
                    viewport: CGSize) -> (pointsPerSecond: Double, tileSize: CGFloat)? {
        let dates = items.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let span = last.timeIntervalSince(first)
        guard span > 0 else { return nil }
        let horizontal = orientation == .horizontal
        let length = horizontal ? viewport.width : viewport.height
        let cross = horizontal ? viewport.height : viewport.width

        var best: (Double, CGFloat)?
        for size in stride(from: maxTileSize, through: minTileSize, by: -4) {
            let pps = Double(max(200, length - 2 * size - 40)) / span
            best = (pps, size)
            let layout = TimelineLayout(items: items, orientation: orientation, pointsPerSecond: pps, tileSize: size)
            if 2 * layout.crossExtentPerSide <= cross { break }
        }
        return best.map { (pointsPerSecond: $0.0, tileSize: $0.1) }
    }

    // MARK: Time ↔ position

    func along(for date: Date) -> CGFloat {
        margin + CGFloat(date.timeIntervalSince(startDate) * pointsPerSecond)
    }

    func date(atAlong along: CGFloat) -> Date {
        startDate.addingTimeInterval(Double(along - margin) / pointsPerSecond)
    }

    // MARK: Extent

    var length: CGFloat { CGFloat(duration * pointsPerSecond) + 2 * margin }

    /// Lanes alternate sides, so each side holds about half of them.
    var crossExtentPerSide: CGFloat {
        let depth = CGFloat((laneCount + 1) / 2)
        return axisGap + depth * (tileSize + gap) + gap
    }

    var contentSize: CGSize {
        let cross = 2 * crossExtentPerSide
        return orientation == .horizontal
            ? CGSize(width: length, height: cross)
            : CGSize(width: cross, height: length)
    }

    // MARK: Axis space → view space

    func point(along: CGFloat, cross: CGFloat) -> CGPoint {
        let c = cross + crossExtentPerSide
        return orientation == .horizontal ? CGPoint(x: along, y: c) : CGPoint(x: c, y: along)
    }

    /// Converts a drag translation into movement along the axis.
    func alongComponent(of translation: CGSize) -> CGFloat {
        orientation == .horizontal ? translation.width : translation.height
    }

    /// The along-axis range a view-space rect covers.
    func alongRange(of rect: CGRect) -> ClosedRange<CGFloat> {
        orientation == .horizontal ? rect.minX...rect.maxX : rect.minY...rect.maxY
    }

    // MARK: Lane assignment

    static func crossCenter(lane: Int, tileSize: CGFloat, gap: CGFloat, axisGap: CGFloat) -> CGFloat {
        let side: CGFloat = lane.isMultiple(of: 2) ? -1 : 1
        let depth = CGFloat(lane / 2)
        return side * (axisGap + tileSize / 2 + depth * (tileSize + gap))
    }

    private mutating func layout(_ items: [Item]) {
        let sorted = items.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else {
            placements = []; laneCount = 0; duration = 0
            return
        }
        startDate = first.date
        duration = last.date.timeIntervalSince(first.date)

        // Greedy interval scheduling: each tile is centered on its time point and
        // goes into the first lane where it doesn't touch the previous tile.
        var laneEnds: [CGFloat] = []
        placements = sorted.map { item in
            let along = along(for: item.date)
            let start = along - tileSize / 2
            let lane = laneEnds.firstIndex { $0 + gap <= start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(0) }
            laneEnds[lane] = start + tileSize
            let cross = Self.crossCenter(lane: lane, tileSize: tileSize, gap: gap, axisGap: axisGap)
            return Placement(id: item.id, along: along, lane: lane, cross: cross)
        }
        laneCount = laneEnds.count
    }
}
