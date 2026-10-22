import CoreGraphics
import Foundation
import Testing
@testable import PhotoTimeline

struct TimelineLayoutTests {
    private func items(_ offsets: [TimeInterval]) -> [TimelineLayout.Item] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return offsets.map { .init(id: UUID(), date: base.addingTimeInterval($0)) }
    }

    private func frame(_ p: TimelineLayout.Placement, _ layout: TimelineLayout) -> CGRect {
        let center = layout.point(along: p.along, cross: p.cross)
        let s = layout.tileSize
        return CGRect(x: center.x - s / 2, y: center.y - s / 2, width: s, height: s)
    }

    @Test(arguments: TimelineOrientation.allCases)
    func tilesNeverOverlap(orientation: TimelineOrientation) {
        // Dense burst plus some spread: worst case for overlap.
        let offsets = (0..<40).map { TimeInterval($0) } + [3600, 3601, 7200]
        let layout = TimelineLayout(items: items(offsets), orientation: orientation, pointsPerSecond: 1)
        let frames = layout.placements.map { frame($0, layout) }
        for i in frames.indices {
            for j in frames.indices where j > i {
                #expect(!frames[i].intersects(frames[j]), "tile \(i) overlaps \(j)")
            }
        }
    }

    @Test func positionIsProportionalToTime() {
        let layout = TimelineLayout(items: items([0, 100, 300]), orientation: .horizontal, pointsPerSecond: 2)
        let along = layout.placements.map(\.along)
        #expect(along[1] - along[0] == 200)
        #expect(along[2] - along[1] == 400)
    }

    @Test func distantItemsShareFirstLane() {
        let layout = TimelineLayout(items: items([0, 1000, 2000]), orientation: .horizontal, pointsPerSecond: 1)
        #expect(layout.placements.allSatisfy { $0.lane == 0 })
        #expect(layout.laneCount == 1)
    }

    @Test func closeItemsAlternateSides() {
        let layout = TimelineLayout(items: items([0, 1, 2]), orientation: .horizontal, pointsPerSecond: 1)
        #expect(layout.placements.map(\.lane) == [0, 1, 2])
        #expect(layout.placements[0].cross < 0)
        #expect(layout.placements[1].cross > 0)
        #expect(layout.placements[2].cross < layout.placements[0].cross)
    }

    @Test func dateRoundTrip() {
        let layout = TimelineLayout(items: items([0, 3600]), orientation: .vertical, pointsPerSecond: 0.1)
        let date = Date(timeIntervalSince1970: 1_700_001_234)
        #expect(abs(layout.date(atAlong: layout.along(for: date)).timeIntervalSince(date)) < 0.001)
    }

    @Test func contentFitsAllTiles() {
        let layout = TimelineLayout(items: items((0..<10).map(TimeInterval.init)), orientation: .vertical, pointsPerSecond: 1)
        let bounds = CGRect(origin: .zero, size: layout.contentSize)
        for p in layout.placements {
            #expect(bounds.contains(frame(p, layout)))
        }
    }

    @Test(arguments: TimelineOrientation.allCases)
    func fitShowsEverythingByShrinkingTiles(orientation: TimelineOrientation) throws {
        // A burst of 10 photos within a minute stacks five lanes per side.
        let items = items((0..<10).map { TimeInterval($0 * 5) } + [86_400 * 30])
        let viewport = orientation == .horizontal ? CGSize(width: 1200, height: 700) : CGSize(width: 700, height: 1200)
        let fit = try #require(TimelineLayout.fit(items: items, orientation: orientation, viewport: viewport))
        #expect(fit.tileSize < TimelineLayout.maxTileSize)

        let layout = TimelineLayout(items: items, orientation: orientation,
                                    pointsPerSecond: fit.pointsPerSecond, tileSize: fit.tileSize)
        #expect(layout.contentSize.width <= viewport.width)
        #expect(layout.contentSize.height <= viewport.height)
    }

    @Test func fitKeepsFullTileSizeWhenThereIsRoom() throws {
        let fit = try #require(TimelineLayout.fit(items: items([0, 3600, 7200]), orientation: .horizontal,
                                                  viewport: CGSize(width: 1200, height: 700)))
        #expect(fit.tileSize == TimelineLayout.maxTileSize)
    }
}
