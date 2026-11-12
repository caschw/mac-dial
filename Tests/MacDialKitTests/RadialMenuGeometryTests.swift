import XCTest
import MacDialKit

final class RadialMenuGeometryTests: XCTestCase {
    func testRootSectorsTileTheCircleFromTwelveOClock() {
        XCTAssertEqual(RadialMenuGeometry.rootSectors(count: 1), [RadialSector(center: 0, span: 360)])
        let sectors = RadialMenuGeometry.rootSectors(count: 4)
        XCTAssertEqual(sectors.map(\.center), [0, 90, 180, 270])
        XCTAssertEqual(sectors[0].start, -45)
        XCTAssertEqual(sectors[3].end, 315)
        for (previous, next) in zip(sectors, sectors.dropFirst()) {
            XCTAssertEqual(previous.end, next.start, accuracy: 1e-9)
        }
        for count in [Int.min, -1, 0] {
            XCTAssertTrue(RadialMenuGeometry.rootSectors(count: count).isEmpty)
        }
    }

    func testVisibleWindowShowsEverythingWhenItFits() {
        XCTAssertEqual(RadialMenuGeometry.visibleWindow(slotCount: 5, selected: 4, maxVisible: 5), 0..<5)
        XCTAssertEqual(RadialMenuGeometry.visibleWindow(slotCount: 1, selected: 0, maxVisible: 7), 0..<1)
    }

    func testVisibleWindowFollowsSelectionAndClampsToEnds() {
        let window = { RadialMenuGeometry.visibleWindow(slotCount: 10, selected: $0, maxVisible: 5) }
        XCTAssertEqual(window(0), 0..<5)
        XCTAssertEqual(window(2), 0..<5)
        XCTAssertEqual(window(3), 1..<6)
        XCTAssertEqual(window(6), 4..<9)
        XCTAssertEqual(window(9), 5..<10)
        for selected in 0..<10 {
            XCTAssertTrue(window(selected)?.contains(selected) == true)
        }
        XCTAssertEqual(RadialMenuGeometry.visibleWindow(slotCount: 10, selected: 5, maxVisible: 4), 3..<7)
    }

    func testVisibleWindowRejectsInvalidInputs() {
        XCTAssertNil(RadialMenuGeometry.visibleWindow(slotCount: 0, selected: 0, maxVisible: 3))
        XCTAssertNil(RadialMenuGeometry.visibleWindow(slotCount: -1, selected: 0, maxVisible: 3))
        XCTAssertNil(RadialMenuGeometry.visibleWindow(slotCount: 3, selected: -1, maxVisible: 3))
        XCTAssertNil(RadialMenuGeometry.visibleWindow(slotCount: 3, selected: 3, maxVisible: 3))
        XCTAssertNil(RadialMenuGeometry.visibleWindow(slotCount: 3, selected: 0, maxVisible: 0))
        XCTAssertNil(RadialMenuGeometry.visibleWindow(slotCount: Int.max, selected: Int.min, maxVisible: Int.max))
        XCTAssertEqual(RadialMenuGeometry.visibleWindow(slotCount: Int.max, selected: Int.max - 1, maxVisible: 3),
                       (Int.max - 3)..<Int.max)
    }

    func testArcSectorsCenterOnAnchor() {
        let arc = RadialMenuGeometry.arcSectors(anchor: 90, count: 3, slotSpan: 30)
        XCTAssertEqual(arc.map(\.center), [60, 90, 120])
        XCTAssertEqual(arc.first?.start, 45)
        XCTAssertEqual(arc.last?.end, 135)
        XCTAssertEqual(RadialMenuGeometry.arcSectors(anchor: 0, count: 2, slotSpan: 30).map(\.center), [-15, 15])
        XCTAssertEqual(RadialMenuGeometry.arcSectors(anchor: 0, count: 12, slotSpan: 30).count, 12)
    }

    func testArcSectorsRejectInvalidInputs() {
        let invalid: [(Double, Int, Double)] = [
            (0, 0, 30), (0, -1, 30), (0, 3, 0), (0, 3, -30), (0, 13, 30),
            (.nan, 3, 30), (.infinity, 3, 30), (0, 3, .nan), (0, 3, .infinity), (0, Int.max, 30),
        ]
        for (anchor, count, span) in invalid {
            XCTAssertTrue(RadialMenuGeometry.arcSectors(anchor: anchor, count: count, slotSpan: span).isEmpty,
                          "\(anchor) \(count) \(span)")
        }
    }

    func testClampedCenterKeepsFootprintOnScreenIncludingNegativeOrigins() {
        let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let size = CGSize(width: 400, height: 400)
        XCTAssertEqual(RadialMenuGeometry.clampedCenter(CGPoint(x: -700, y: 250), footprint: size, in: screen),
                       CGPoint(x: -700, y: 250))
        XCTAssertEqual(RadialMenuGeometry.clampedCenter(CGPoint(x: -1430, y: -190), footprint: size, in: screen),
                       CGPoint(x: -1240, y: 0))
        XCTAssertEqual(RadialMenuGeometry.clampedCenter(CGPoint(x: 50, y: 900), footprint: size, in: screen),
                       CGPoint(x: -200, y: 500))
    }

    func testClampedCenterCentersAxesThatCannotFit() {
        let screen = CGRect(x: 0, y: 0, width: 300, height: 1000)
        XCTAssertEqual(RadialMenuGeometry.clampedCenter(CGPoint(x: 10, y: 10),
                                                        footprint: CGSize(width: 400, height: 200), in: screen),
                       CGPoint(x: 150, y: 100))
    }

    func testClampedCenterHandlesInvalidInputs() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let center = CGPoint(x: 500, y: 400)
        XCTAssertEqual(RadialMenuGeometry.clampedCenter(CGPoint(x: CGFloat.nan, y: .infinity),
                                                        footprint: CGSize(width: 100, height: 100), in: screen),
                       center)
        XCTAssertEqual(RadialMenuGeometry.clampedCenter(CGPoint(x: 2000, y: -5),
                                                        footprint: CGSize(width: -100, height: CGFloat.nan),
                                                        in: screen),
                       CGPoint(x: 1000, y: 0), "negative or non-finite sizes act as a point")
        XCTAssertEqual(RadialMenuGeometry.clampedCenter(CGPoint(x: 5, y: 5), footprint: .zero,
                                                        in: CGRect(x: 100, y: 100, width: -50, height: -50)),
                       CGPoint(x: 50, y: 50), "negative-size bounds are standardized")
        for bounds in [CGRect.null, CGRect.infinite, CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)] {
            XCTAssertEqual(RadialMenuGeometry.clampedCenter(CGPoint(x: 7, y: 8), footprint: .zero, in: bounds),
                           CGPoint(x: 7, y: 8))
        }
    }
}
