import XCTest
import MacDialKit

final class RadialMenuNavigationTests: XCTestCase {
    private typealias Item = RadialMenuItem<Int>

    private let tree: [Item] = [
        .leaf(id: "a", title: "A", symbol: "a.circle", payload: 1),
        .group(id: "g", title: "Group", symbol: "folder", children: [
            .leaf(id: "g1", title: "G1", symbol: "1.circle", payload: 11),
            .group(id: "h", title: "Nested", symbol: "folder.fill", children: [
                .leaf(id: "h1", title: "H1", symbol: "h.circle", payload: 21),
            ]),
            .leaf(id: "g2", title: "G2", symbol: "2.circle", payload: 12),
        ]),
        .leaf(id: "b", title: "B", symbol: "b.circle", payload: 2),
    ]

    private func ids<P>(_ slots: [RadialMenuSlot<P>]) -> [String] {
        slots.map { $0.item?.id ?? "<back>" }
    }

    private func leafPayload(_ result: RadialMenuConfirmation<Int>) -> Int? {
        guard case .selectedLeaf(let item) = result, case .leaf(let payload) = item.content else { return nil }
        return payload
    }

    func testValidationRejectsInvalidInputs() {
        XCTAssertThrowsError(try RadialMenuNavigation<Int>(items: [], selectedID: nil, detentsPerItem: 1)) {
            XCTAssertEqual($0 as? RadialMenuValidationError, .emptyMenu)
        }
        for detents in [Int.min, -1, 0] {
            XCTAssertThrowsError(try RadialMenuNavigation(items: tree, selectedID: nil, detentsPerItem: detents)) {
                XCTAssertEqual($0 as? RadialMenuValidationError, .invalidDetentsPerItem(detents))
            }
        }
        let emptyGroup: [Item] = [.leaf(id: "a", title: "A", symbol: "", payload: 0),
                                  .group(id: "e", title: "E", symbol: "", children: [])]
        XCTAssertThrowsError(try RadialMenuNavigation(items: emptyGroup, selectedID: nil, detentsPerItem: 1)) {
            XCTAssertEqual($0 as? RadialMenuValidationError, .emptyGroup(id: "e"))
        }
        let nestedEmpty: [Item] = [.group(id: "o", title: "O", symbol: "", children: [
            .group(id: "i", title: "I", symbol: "", children: []),
        ])]
        XCTAssertThrowsError(try RadialMenuNavigation(items: nestedEmpty, selectedID: nil, detentsPerItem: 1)) {
            XCTAssertEqual($0 as? RadialMenuValidationError, .emptyGroup(id: "i"))
        }
        let duplicateAcrossLevels: [Item] = [.leaf(id: "x", title: "X", symbol: "", payload: 0),
                                             .group(id: "g", title: "G", symbol: "", children: [
                                                 .leaf(id: "x", title: "X2", symbol: "", payload: 1),
                                             ])]
        XCTAssertThrowsError(try RadialMenuNavigation(items: duplicateAcrossLevels, selectedID: nil,
                                                      detentsPerItem: 1)) {
            XCTAssertEqual($0 as? RadialMenuValidationError, .duplicateID("x"))
        }
    }

    func testInitialSelectionUsesMatchingRootIDOrFallsBackToFirst() throws {
        XCTAssertEqual(try RadialMenuNavigation(items: tree, selectedID: "b", detentsPerItem: 1)
            .current.selection.selected, 2)
        for missing in [nil, "missing", "g1"] as [String?] {
            let navigation = try RadialMenuNavigation(items: tree, selectedID: missing, detentsPerItem: 1)
            XCTAssertEqual(navigation.current.selection.selected, 0)
        }
        let navigation = try RadialMenuNavigation(items: tree, selectedID: nil, detentsPerItem: 1)
        XCTAssertEqual(navigation.depth, 0)
        XCTAssertTrue(navigation.breadcrumb.isEmpty)
        XCTAssertNil(navigation.root.group)
        XCTAssertEqual(ids(navigation.root.slots), ["a", "g", "b"])
    }

    func testConfirmingLeafAtRootSelectsItWithoutChangingLevels() throws {
        var navigation = try RadialMenuNavigation(items: tree, selectedID: "b", detentsPerItem: 1)
        XCTAssertEqual(leafPayload(navigation.confirm()), 2)
        XCTAssertEqual(navigation.depth, 0)
    }

    func testEnteringGroupOpensArcWithBackAndSelectsFirstChild() throws {
        var navigation = try RadialMenuNavigation(items: tree, selectedID: "g", detentsPerItem: 1)
        guard case .enteredGroup(let group) = navigation.confirm() else { return XCTFail("expected group") }
        XCTAssertEqual(group.id, "g")
        XCTAssertEqual(navigation.depth, 1)
        XCTAssertEqual(navigation.breadcrumb, ["Group"])
        XCTAssertEqual(navigation.current.group?.id, "g")
        XCTAssertEqual(ids(navigation.current.slots), ["<back>", "g1", "h", "g2"])
        XCTAssertEqual(navigation.current.selectedSlot.item?.id, "g1")
        XCTAssertEqual(navigation.root.selection.selected, 1, "root keeps its selection while subdued")

        XCTAssertEqual(leafPayload(navigation.confirm()), 11)
        XCTAssertEqual(navigation.depth, 1)
    }

    func testMovementOnlyAffectsActiveLevelAndWrapsOntoBack() throws {
        var navigation = try RadialMenuNavigation(items: tree, selectedID: "g", detentsPerItem: 1)
        _ = navigation.confirm()
        XCTAssertTrue(navigation.move(by: -1))
        guard case .back = navigation.current.selectedSlot else { return XCTFail("expected back") }
        XCTAssertTrue(navigation.move(by: -1))
        XCTAssertEqual(navigation.current.selectedSlot.item?.id, "g2")
        XCTAssertEqual(navigation.root.selection.selected, 1)
        XCTAssertFalse(navigation.move(by: 0))
    }

    func testBackRestoresParentSelectionAcrossNestedLevels() throws {
        var navigation = try RadialMenuNavigation(items: tree, selectedID: "g", detentsPerItem: 1)
        _ = navigation.confirm()
        navigation.move(by: 1)
        guard case .enteredGroup(let nested) = navigation.confirm() else { return XCTFail("expected group") }
        XCTAssertEqual(nested.id, "h")
        XCTAssertEqual(navigation.depth, 2)
        XCTAssertEqual(navigation.breadcrumb, ["Group", "Nested"])
        XCTAssertEqual(ids(navigation.current.slots), ["<back>", "h1"])
        XCTAssertEqual(leafPayload(navigation.confirm()), 21)

        navigation.move(by: -1)
        guard case .returned = navigation.confirm() else { return XCTFail("expected return") }
        XCTAssertEqual(navigation.depth, 1)
        XCTAssertEqual(navigation.current.selectedSlot.item?.id, "h")

        navigation.move(by: -2)
        guard case .returned = navigation.confirm() else { return XCTFail("expected return") }
        XCTAssertEqual(navigation.depth, 0)
        XCTAssertEqual(navigation.current.selectedSlot.item?.id, "g")
        XCTAssertTrue(navigation.breadcrumb.isEmpty)

        guard case .enteredGroup = navigation.confirm() else { return XCTFail("expected group") }
        XCTAssertEqual(navigation.current.selectedSlot.item?.id, "g1", "re-entry starts at first child")
    }

    func testLevelChangesDiscardPartialDetents() throws {
        var navigation = try RadialMenuNavigation(items: tree, selectedID: "g", detentsPerItem: 2)
        XCTAssertFalse(navigation.move(by: 1))
        _ = navigation.confirm()
        XCTAssertFalse(navigation.move(by: 1), "new arc starts without parent's partial detent")
        XCTAssertTrue(navigation.move(by: 1))
        XCTAssertEqual(navigation.current.selectedSlot.item?.id, "h")
        XCTAssertFalse(navigation.move(by: 1))
        navigation.move(by: -5)
        guard case .back = navigation.current.selectedSlot else { return XCTFail("expected back") }
        guard case .returned = navigation.confirm() else { return XCTFail("expected return") }
        XCTAssertFalse(navigation.move(by: 1), "parent partial detent was discarded on entry")
        XCTAssertTrue(navigation.move(by: 1))
        XCTAssertEqual(navigation.current.selectedSlot.item?.id, "b")
    }

    func testDiscardPartialMovementClearsRemainderInBothDirections() throws {
        var selection = try XCTUnwrap(RadialMenuSelection(itemCount: 3, selected: 1, detentsPerItem: 3))
        selection.move(by: 2)
        selection.discardPartialMovement()
        XCTAssertFalse(selection.move(by: 2))
        selection.discardPartialMovement()
        XCTAssertFalse(selection.move(by: -2))
        selection.discardPartialMovement()
        XCTAssertTrue(selection.move(by: -3))
        XCTAssertEqual(selection.selected, 0)
    }

    func testItemHelpers() {
        XCTAssertFalse(tree[0].isGroup)
        XCTAssertTrue(tree[1].isGroup)
        XCTAssertNil(RadialMenuSlot<Int>.back.item)
        XCTAssertEqual(RadialMenuSlot.item(tree[0]).item?.title, "A")
    }
}
