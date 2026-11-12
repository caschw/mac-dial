import XCTest
import MacDialKit

final class RotationEffectQueueTests: XCTestCase {
    func testOrdinaryBurstsAndActionsExecuteSynchronously() {
        var turns: [() -> Void] = []
        var delivered: [String] = []
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) },
                                        perform: { _, _ in delivered.append("rotation") })
        let binding = RotationBinding(.zoom, steps: 1)
        queue.enqueue(RotationInterpreter().rotate(binding, delta: 3, at: 0), for: binding)
        queue.enqueueAction { delivered.append("action") }
        XCTAssertEqual(delivered, ["rotation", "rotation", "rotation", "action"])
        XCTAssertTrue(turns.isEmpty)
    }

    func testLargeAuxiliaryBurstsYieldWithoutDroppingEventsAndKeepOrder() {
        var turns: [() -> Void] = []
        var delivered: [RotationEffect] = []
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) },
                                        perform: { _, effect in delivered.append(effect) })
        let rotation = RotationInterpreter()
        let volume = RotationBinding(.volume, speed: 4.5)
        queue.enqueue(rotation.rotate(volume, delta: -128, at: 0), for: volume)
        XCTAssertEqual(delivered, [.auxiliary(action: .volume, increasing: false, repeatCount: 512)])
        XCTAssertEqual(turns.count, 1)

        let brightness = RotationBinding(.brightness)
        queue.enqueueAction { delivered.append(.discrete(forward: false)) }
        queue.enqueue(rotation.rotate(brightness, delta: 1, at: 0.1), for: brightness)
        XCTAssertEqual(delivered.count, 1)
        turns.removeFirst()()
        XCTAssertEqual(delivered, [
            .auxiliary(action: .volume, increasing: false, repeatCount: 512),
            .auxiliary(action: .volume, increasing: false, repeatCount: 128),
            .discrete(forward: false),
            .auxiliary(action: .brightness, increasing: true, repeatCount: 1)
        ])
        XCTAssertTrue(turns.isEmpty)
    }

    func testLargeDiscreteSequencesAreProcessedInBoundedTurns() {
        var turns: [() -> Void] = []
        var delivered: [RotationEffect] = []
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) },
                                        perform: { _, effect in delivered.append(effect) })
        let binding = RotationBinding(.zoom, steps: 1)
        queue.enqueue(RotationInterpreter().rotate(binding, delta: 1025, at: 0), for: binding)
        XCTAssertEqual(delivered.count, 512)
        turns.removeFirst()()
        XCTAssertEqual(delivered.count, 1024)
        turns.removeFirst()()
        XCTAssertEqual(delivered.count, 1025)
        XCTAssertTrue(delivered.allSatisfy { $0 == .discrete(forward: true) })
        XCTAssertTrue(turns.isEmpty)
    }

    func testEquivalentAuxiliaryPartitionsDeliverTheSameNumberOfEvents() {
        func deliveredCounts(_ deltas: [Int]) -> Int {
            var turns: [() -> Void] = []
            var total = 0
            let queue = RotationEffectQueue(scheduleNext: { turns.append($0) }) { _, effect in
                if case .auxiliary(_, _, let count) = effect { total += count }
            }
            let binding = RotationBinding(.volume, speed: 4.5)
            let rotation = RotationInterpreter()
            for delta in deltas { queue.enqueue(rotation.rotate(binding, delta: delta, at: 0), for: binding) }
            while !turns.isEmpty { turns.removeFirst()() }
            return total
        }
        XCTAssertEqual(deliveredCounts([-128]), 640)
        XCTAssertEqual(deliveredCounts([-64, -64]), 640)
    }

    func testCancellationDoesNotRunAStaleScheduledTurn() {
        var turns: [() -> Void] = []
        var delivered = 0
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) },
                                        perform: { _, _ in delivered += 1 })
        let binding = RotationBinding(.switchApps, steps: 1)
        queue.enqueue(RotationInterpreter().rotate(binding, delta: 513, at: 0), for: binding)
        XCTAssertEqual(delivered, 512)
        queue.cancelPending()

        queue.enqueue(RotationInterpreter().rotate(binding, delta: 513, at: 0), for: binding)
        XCTAssertEqual(delivered, 1024)
        turns.removeFirst()()
        XCTAssertEqual(delivered, 1024)
        turns.removeFirst()()
        XCTAssertEqual(delivered, 1025)
    }

    func testReentrantEnqueuesRemainBehindTheCurrentBurst() {
        var turns: [() -> Void] = []
        var delivered: [String] = []
        var queue: RotationEffectQueue!
        let binding = RotationBinding(.zoom, steps: 1)
        let rotation = RotationInterpreter()
        queue = RotationEffectQueue(scheduleNext: { turns.append($0) }) { _, _ in
            delivered.append("rotation")
            if delivered.count == 1 {
                queue.enqueueAction { delivered.append("action") }
                queue.enqueue(rotation.rotate(binding, delta: 1, at: 0.1), for: binding)
            }
        }
        queue.enqueue(rotation.rotate(binding, delta: 513, at: 0), for: binding)
        XCTAssertEqual(delivered.count, 512)
        turns.removeFirst()()
        XCTAssertEqual(delivered.count, 515)
        XCTAssertEqual(delivered[512...].map { $0 }, ["rotation", "action", "rotation"])
        queue = nil
    }

    func testExcessiveRotationsAreRejectedAndActionsRemainResponsive() {
        var turns: [() -> Void] = []
        var delivered = 0
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) },
                                        perform: { _, _ in delivered += 1 })
        let binding = RotationBinding(.zoom, steps: 1)
        XCTAssertFalse(queue.enqueue(RotationInterpreter().rotate(binding, delta: Int.min, at: 0), for: binding))
        let volume = RotationBinding(.volume, speed: 1_000_000_000)
        XCTAssertFalse(queue.enqueue(RotationInterpreter().rotate(volume, delta: -128, at: 0), for: volume))
        queue.enqueueAction { delivered += 1 }
        XCTAssertEqual(delivered, 1)
        XCTAssertTrue(turns.isEmpty)
    }

    func testOutstandingRotationWorkIsBoundedWithoutDroppingAcceptedEvents() {
        var turns: [() -> Void] = []
        var delivered = 0
        var actionRan = false
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) },
                                        perform: { _, _ in delivered += 1 })
        let binding = RotationBinding(.zoom, steps: 1)
        let rotation = RotationInterpreter()
        XCTAssertTrue(queue.enqueue(rotation.rotate(binding, delta: 4096, at: 0), for: binding))
        XCTAssertFalse(queue.enqueue(rotation.rotate(binding, delta: 1024, at: 0.1), for: binding))
        queue.enqueueAction {
            XCTAssertEqual(delivered, 4096)
            actionRan = true
        }
        turns.removeFirst()()
        XCTAssertTrue(queue.enqueue(rotation.rotate(binding, delta: 1024, at: 0.2), for: binding))
        while !turns.isEmpty { turns.removeFirst()() }
        XCTAssertEqual(delivered, 5120)
        XCTAssertTrue(actionRan)
    }

    func testMouseReleaseFollowsAnOrdinaryBurst() {
        var turns: [() -> Void] = []
        var buttons: [Bool] = []
        var delivered = 0
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) }) { _, effect in
            if case .auxiliary(_, _, let count) = effect { delivered += count }
        }
        queue.enqueueMouseButton(.leftClick, down: true) { buttons.append($0) }
        let volume = RotationBinding(.volume, speed: 4.5)
        queue.enqueue(RotationInterpreter().rotate(volume, delta: -128, at: 0), for: volume)
        queue.enqueueMouseButton(.leftClick, down: false) { buttons.append($0) }
        XCTAssertEqual(buttons, [true])
        turns.removeFirst()()
        XCTAssertEqual(delivered, 640)
        XCTAssertEqual(buttons, [true, false])
        queue.cancelPending()
        XCTAssertEqual(buttons, [true, false])
    }

    func testCancellationReleasesDeliveredMouseDownAndDropsQueuedRelease() {
        var turns: [() -> Void] = []
        var buttons: [String] = []
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) },
                                        perform: { _, _ in })
        queue.enqueueMouseButton(.leftClick, down: true) { buttons.append($0 ? "down" : "up") }
        let volume = RotationBinding(.volume, speed: 4.5)
        queue.enqueue(RotationInterpreter().rotate(volume, delta: -128, at: 0), for: volume)
        queue.enqueueMouseButton(.leftClick, down: false) { buttons.append($0 ? "down" : "up") }
        XCTAssertEqual(buttons, ["down"])
        queue.cancelPending()
        XCTAssertEqual(buttons, ["down", "up"])
        turns.removeFirst()()
        XCTAssertEqual(buttons, ["down", "up"])
    }

    func testCancellationDoesNotPressOrReleaseAnUndeliveredMouseButton() {
        var turns: [() -> Void] = []
        var buttons: [Bool] = []
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) },
                                        perform: { _, _ in })
        let binding = RotationBinding(.zoom, steps: 1)
        queue.enqueue(RotationInterpreter().rotate(binding, delta: 513, at: 0), for: binding)
        queue.enqueueMouseButton(.rightClick, down: true) { buttons.append($0) }
        queue.enqueueMouseButton(.rightClick, down: false) { buttons.append($0) }
        queue.cancelPending()
        turns.removeFirst()()
        XCTAssertTrue(buttons.isEmpty)
    }

    func testCancellationDuringMouseDownStillBalancesTheButton() {
        var buttons: [Bool] = []
        var queue: RotationEffectQueue!
        queue = RotationEffectQueue(scheduleNext: { _ in }, perform: { _, _ in })
        queue.enqueueMouseButton(.middleClick, down: true) { down in
            buttons.append(down)
            if down { queue.cancelPending() }
        }
        XCTAssertEqual(buttons, [true, false])
        queue = nil
    }

    func testReplacingMouseReleaseAllowsDeinitializationToCancelTheQueue() {
        var events: [String] = []
        let queue = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                        perform: { _, _ in })
        var probe: DeinitProbe? = DeinitProbe { queue.cancelPending() }
        queue.enqueueMouseButton(.leftClick, down: true) { [held = probe!] down in
            withExtendedLifetime(held) { events.append(down ? "first down" : "first up") }
        }
        probe = nil
        queue.enqueueMouseButton(.leftClick, down: true) {
            events.append($0 ? "second down" : "second up")
        }

        XCTAssertEqual(events, ["first down", "second down", "second up"])
    }

    func testNonMouseActionCannotEnterMouseQueue() {
        var buttons: [Bool] = []
        let queue = RotationEffectQueue(scheduleNext: { _ in }, perform: { _, _ in })
        queue.enqueueMouseButton(.mute, down: true) { buttons.append($0) }
        queue.cancelPending()
        XCTAssertTrue(buttons.isEmpty)
    }

    func testCancellationFromAnActionDropsLaterWork() {
        var turns: [() -> Void] = []
        var delivered: [String] = []
        var queue: RotationEffectQueue!
        let binding = RotationBinding(.zoom, steps: 1)
        queue = RotationEffectQueue(scheduleNext: { turns.append($0) },
                                    perform: { _, _ in delivered.append("rotation") })
        queue.enqueue(RotationInterpreter().rotate(binding, delta: 513, at: 0), for: binding)
        queue.enqueueAction {
            delivered.append("cancel")
            queue.cancelPending()
        }
        queue.enqueueAction { delivered.append("unexpected") }
        turns.removeFirst()()
        XCTAssertEqual(delivered.count, 514)
        XCTAssertEqual(delivered.last, "cancel")
        XCTAssertTrue(turns.isEmpty)
        queue = nil
    }

    func testCancellingWorkAllowsCapturedObjectsToEnqueueDuringDeinitialization() {
        var turns: [() -> Void] = []
        var events: [String] = []
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) }, perform: { _, _ in })
        let binding = RotationBinding(.zoom, steps: 1)
        XCTAssertTrue(queue.enqueue(RotationInterpreter().rotate(binding, delta: 513, at: 0), for: binding))

        var probe: DeinitProbe? = DeinitProbe {
            queue.enqueueAction { events.append("deinitialized") }
        }
        queue.enqueueAction { [held = probe!] in withExtendedLifetime(held) {} }
        probe = nil

        queue.cancelPending()
        XCTAssertEqual(events, ["deinitialized"])
        turns.removeFirst()()
        XCTAssertEqual(events, ["deinitialized"])
    }

    func testDrainingWorkAllowsCapturedObjectsToEnqueueDuringDeinitialization() {
        var turns: [() -> Void] = []
        var events: [String] = []
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) }, perform: { _, _ in })
        let binding = RotationBinding(.zoom, steps: 1)
        XCTAssertTrue(queue.enqueue(RotationInterpreter().rotate(binding, delta: 513, at: 0), for: binding))

        var probe: DeinitProbe? = DeinitProbe {
            queue.enqueueAction { events.append("deinitialized") }
        }
        queue.enqueueAction { [held = probe!] in
            withExtendedLifetime(held) { events.append("action") }
        }
        probe = nil

        turns.removeFirst()()
        XCTAssertEqual(events, ["action", "deinitialized"])
        XCTAssertTrue(turns.isEmpty)
    }

    func testCompletionFollowsTheFinalEffectAndPrecedesLaterActions() {
        var turns: [() -> Void] = []
        var delivered = 0
        var markers: [String] = []
        let queue = RotationEffectQueue(scheduleNext: { turns.append($0) },
                                        perform: { _, _ in delivered += 1 })
        let binding = RotationBinding(.zoom, steps: 1)
        XCTAssertTrue(queue.enqueue(RotationInterpreter().rotate(binding, delta: 513, at: 0), for: binding,
                                    onComplete: { markers.append("complete") }))
        queue.enqueueAction { markers.append("action") }
        XCTAssertEqual(delivered, 512)
        XCTAssertTrue(markers.isEmpty)
        turns.removeFirst()()
        XCTAssertEqual(delivered, 513)
        XCTAssertEqual(markers, ["complete", "action"])
    }

    func testEmptyAndRejectedRotationsDoNotCallCompletion() {
        var completed = false
        let queue = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                        perform: { _, _ in XCTFail("Unexpected effect") })
        let binding = RotationBinding(.zoom, steps: 1)
        XCTAssertTrue(queue.enqueue(RotationInterpreter().rotate(binding, delta: 0, at: 0), for: binding,
                                    onComplete: { completed = true }))
        XCTAssertFalse(queue.enqueue(RotationInterpreter().rotate(binding, delta: 4097, at: 0), for: binding,
                                     onComplete: { completed = true }))
        XCTAssertFalse(completed)
    }

    func testCancellationDuringFinalEffectSkipsCompletion() {
        var completed = false
        var queue: RotationEffectQueue!
        queue = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                    perform: { _, _ in queue.cancelPending() })
        let binding = RotationBinding(.zoom, steps: 1)
        XCTAssertTrue(queue.enqueue(RotationInterpreter().rotate(binding, delta: 1, at: 0), for: binding,
                                    onComplete: { completed = true }))
        XCTAssertFalse(completed)
        queue = nil
    }
}

private final class DeinitProbe {
    private let onDeinit: () -> Void

    init(_ onDeinit: @escaping () -> Void) {
        self.onDeinit = onDeinit
    }

    deinit { onDeinit() }
}
