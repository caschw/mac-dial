import XCTest
import MacDialKit

final class RadialMenuSelectionTests: XCTestCase {
    func testInvalidMenuInputsAreRejected() {
        for detents in [Int.min, -1, 0] {
            XCTAssertNil(RadialMenuSelection(itemCount: 3, selected: 0, detentsPerItem: detents))
        }
        XCTAssertNil(RadialMenuSelection(itemCount: 0, selected: 0, detentsPerItem: 1))
        XCTAssertNil(RadialMenuSelection(itemCount: -1, selected: 0, detentsPerItem: 1))
        XCTAssertNil(RadialMenuSelection(itemCount: 3, selected: -1, detentsPerItem: 1))
        XCTAssertNil(RadialMenuSelection(itemCount: 3, selected: 3, detentsPerItem: 1))
    }

    func testRemainderReversalAndWrapping() throws {
        var selection = try XCTUnwrap(RadialMenuSelection(itemCount: 3, selected: 0, detentsPerItem: 2))
        XCTAssertFalse(selection.move(by: 1))
        XCTAssertFalse(selection.move(by: -1))
        XCTAssertFalse(selection.move(by: -1))
        XCTAssertTrue(selection.move(by: -1))
        XCTAssertEqual(selection.selected, 2)
        XCTAssertEqual(selection.continuousSelection, -1)
        XCTAssertTrue(selection.move(by: 8))
        XCTAssertEqual(selection.selected, 0)
        XCTAssertEqual(selection.continuousSelection, 3)
        XCTAssertFalse(selection.move(by: 0))
    }

    func testExtremeDeltasAndThresholdsDoNotOverflowOrIteratePerDetent() throws {
        var selection = try XCTUnwrap(RadialMenuSelection(itemCount: 3, selected: 1, detentsPerItem: 1))
        XCTAssertTrue(selection.move(by: Int.max))
        XCTAssertEqual(selection.selected, 2)
        XCTAssertEqual(selection.continuousSelection, 2)
        XCTAssertTrue(selection.move(by: Int.min))
        XCTAssertEqual(selection.selected, 0)
        XCTAssertEqual(selection.continuousSelection, Int.min + 2)

        var highThreshold = try XCTUnwrap(RadialMenuSelection(itemCount: 2, selected: 0, detentsPerItem: Int.max))
        XCTAssertFalse(highThreshold.move(by: Int.max - 1))
        XCTAssertTrue(highThreshold.move(by: Int.max))
        XCTAssertEqual(highThreshold.selected, 1)
        XCTAssertFalse(highThreshold.move(by: -1))
        XCTAssertFalse(highThreshold.move(by: Int.min))
        XCTAssertTrue(highThreshold.move(by: -Int.max))
        XCTAssertEqual(highThreshold.selected, 0)
    }

    func testMixedSmallDeltasMatchStepwiseSelection() throws {
        for count in [1, 2, 3, 7] {
            for threshold in [1, 2, 3, 7] {
                for start in 0..<count {
                    var selection = try XCTUnwrap(RadialMenuSelection(itemCount: count, selected: start,
                                                                       detentsPerItem: threshold))
                    var remainder = 0
                    var continuous = start
                    for delta in -8...8 {
                        remainder += delta
                        var changed = false
                        while abs(remainder) >= threshold {
                            let step = remainder > 0 ? 1 : -1
                            remainder -= step * threshold
                            continuous += step
                            changed = true
                        }
                        XCTAssertEqual(selection.move(by: delta), changed)
                        XCTAssertEqual(selection.continuousSelection, continuous)
                        XCTAssertEqual(selection.selected, ((continuous % count) + count) % count)
                    }
                }
            }
        }
    }
}
