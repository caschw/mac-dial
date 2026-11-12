import XCTest
import MacDialKit

final class RotationTests: XCTestCase {
    func testDiscreteThresholdRemainderAndMultipleSteps() {
        let rotation = RotationInterpreter()
        let binding = RotationBinding(.switchTabs, steps: 3)
        assertEffects(rotation.rotate(binding, delta: 2, at: 0), [])
        assertEffects(rotation.rotate(binding, delta: 5, at: 0.1),
                      [.discrete(forward: true), .discrete(forward: true)])
        assertEffects(rotation.rotate(binding, delta: 2, at: 0.2), [.discrete(forward: true)])
    }

    func testDirectionChangeResetsRemainderAndReversalChangesDirection() {
        let rotation = RotationInterpreter()
        var binding = RotationBinding(.switchTabs, steps: 3)
        assertEffects(rotation.rotate(binding, delta: 2, at: 0), [])
        assertEffects(rotation.rotate(binding, delta: -2, at: 0.1), [])
        assertEffects(rotation.rotate(binding, delta: -1, at: 0.2), [.discrete(forward: false)])
        binding.reversed = true
        assertEffects(rotation.rotate(binding, delta: 3, at: 0.3), [.discrete(forward: false)])
    }

    func testPauseThresholdAndBindingChangeResetAccumulation() {
        let rotation = RotationInterpreter()
        let binding = RotationBinding(.switchTabs, steps: 3)
        assertEffects(rotation.rotate(binding, delta: 2, at: 0), [])
        assertEffects(rotation.rotate(binding, delta: 1, at: 0.8), [.discrete(forward: true)])
        assertEffects(rotation.rotate(binding, delta: 2, at: 1), [])
        assertEffects(rotation.rotate(binding, delta: 1, at: 1.801), [])
        assertEffects(rotation.rotate(RotationBinding(.mediaTracks, steps: 3), delta: 2, at: 1.9), [])
        assertEffects(rotation.rotate(RotationBinding(.mediaTracks, steps: 2), delta: 1, at: 2), [])
    }

    func testNonpositiveStepsClampAndNoOpDoesNotConsumeInput() {
        let rotation = RotationInterpreter()
        let binding = RotationBinding(.zoom, steps: 0)
        assertEffects(rotation.rotate(binding, delta: 0, at: 0), [])
        assertEffects(rotation.rotate(RotationBinding(.none), delta: 10, at: 0), [])
        assertEffects(rotation.rotate(binding, delta: -2, at: 1),
                      [.discrete(forward: false), .discrete(forward: false)])
    }

    func testScrollAccelerationSpeedAxisAndReversal() {
        let rotation = RotationInterpreter()
        let vertical = RotationBinding(.scrollVertical)
        assertEffects(rotation.rotate(vertical, delta: 1, at: 0), [.scroll(vertical: -14, horizontal: 0)])
        assertEffects(rotation.rotate(vertical, delta: 1, at: 0.03), [.scroll(vertical: -56, horizontal: 0)])
        let horizontal = RotationBinding(.scrollHorizontal, reversed: true, speed: 2)
        assertEffects(rotation.rotate(horizontal, delta: 2, at: 1), [.scroll(vertical: 0, horizontal: 56)])
    }

    func testVolumeAndBrightnessUseDirectionMagnitudeAndRoundedSpeed() {
        let rotation = RotationInterpreter()
        assertEffects(rotation.rotate(RotationBinding(.volume, speed: 1.6), delta: -3, at: 0),
                      [.auxiliary(action: .volume, increasing: false, repeatCount: 6)])
        assertEffects(rotation.rotate(RotationBinding(.brightness, reversed: true, speed: 0.2), delta: -2, at: 0.1),
                      [.auxiliary(action: .brightness, increasing: true, repeatCount: 2)])
    }

    func testAggregateDeltasMatchEquivalentReportPartitions() {
        let binding = RotationBinding(.switchTabs, steps: 3)
        for delta in [128, -129, 256, -256] {
            let whole = RotationInterpreter()
            let parts = RotationInterpreter()
            let first = delta / 2
            let expected = Array(parts.rotate(binding, delta: first, at: 0)) +
                Array(parts.rotate(binding, delta: delta - first, at: 0.1))
            assertEffects(whole.rotate(binding, delta: delta, at: 0), expected, "delta \(delta)")
        }
        assertEffects(RotationInterpreter().rotate(RotationBinding(.zoom, steps: 128, reversed: true),
                                                   delta: -128, at: 0), [.discrete(forward: true)])
    }

    func testEverySignedReportDeltaProducesTheExpectedDiscreteEffects() {
        for delta in Int(Int8.min)...Int(Int8.max) {
            for steps in [1, 2, 3, 7, 128, Int.max] {
                for reversed in [false, true] {
                    let binding = RotationBinding(.zoom, steps: steps, reversed: reversed)
                    let direction = reversed ? -delta : delta
                    let expected = Array(repeating: RotationEffect.discrete(forward: direction > 0),
                                         count: abs(direction) / steps)
                    assertEffects(RotationInterpreter().rotate(binding, delta: delta, at: 0), expected,
                                  "delta \(delta), steps \(steps), reversed \(reversed)")
                }
            }
        }
    }

    func testNonfiniteTimestampsDoNotConsumeRotationOrChangeTiming() {
        let rotation = RotationInterpreter()
        let binding = RotationBinding(.switchTabs, steps: 3)
        assertEffects(rotation.rotate(binding, delta: 2, at: 0), [])
        for timestamp in [Double.nan, .infinity, -.infinity] {
            assertEffects(rotation.rotate(binding, delta: 1, at: timestamp), [])
        }
        assertEffects(rotation.rotate(binding, delta: 1, at: 0.1), [.discrete(forward: true)])
    }

    func testClockMovingBackwardsActsLikePauseForScrollAndDiscreteActions() {
        let scroll = RotationInterpreter()
        let vertical = RotationBinding(.scrollVertical)
        assertEffects(scroll.rotate(vertical, delta: 1, at: 10), [.scroll(vertical: -14, horizontal: 0)])
        assertEffects(scroll.rotate(vertical, delta: 1, at: 9), [.scroll(vertical: -14, horizontal: 0)])
        assertEffects(scroll.rotate(vertical, delta: 1, at: 9.03), [.scroll(vertical: -56, horizontal: 0)])

        let discrete = RotationInterpreter()
        let binding = RotationBinding(.zoom, steps: 3)
        assertEffects(discrete.rotate(binding, delta: 2, at: 10), [])
        assertEffects(discrete.rotate(binding, delta: 1, at: 9), [])
        assertEffects(discrete.rotate(binding, delta: 2, at: 9.1), [.discrete(forward: true)])

        let extreme = RotationInterpreter()
        assertEffects(extreme.rotate(vertical, delta: 1, at: -.greatestFiniteMagnitude),
                      [.scroll(vertical: -14, horizontal: 0)])
        assertEffects(extreme.rotate(vertical, delta: 1, at: .greatestFiniteMagnitude),
                      [.scroll(vertical: -14, horizontal: 0)])
    }

    func testInvalidContinuousSpeedsAreRejectedWithoutChangingTheClock() {
        let rotation = RotationInterpreter()
        let valid = RotationBinding(.scrollVertical)
        assertEffects(rotation.rotate(valid, delta: 1, at: 0), [.scroll(vertical: -14, horizontal: 0)])
        for speed in [Double.nan, .infinity, -.infinity, -1, .greatestFiniteMagnitude] {
            assertEffects(rotation.rotate(RotationBinding(.scrollVertical, speed: speed), delta: 1, at: 0.03), [])
        }
        assertEffects(rotation.rotate(valid, delta: 1, at: 0.03), [.scroll(vertical: -56, horizontal: 0)])
        assertEffects(RotationInterpreter().rotate(RotationBinding(.scrollVertical, speed: 0), delta: 1, at: 0),
                      [.scroll(vertical: 0, horizontal: 0)])
        assertEffects(RotationInterpreter().rotate(RotationBinding(.volume, speed: 0), delta: 1, at: 0),
                      [.auxiliary(action: .volume, increasing: true, repeatCount: 1)])
        assertEffects(RotationInterpreter().rotate(RotationBinding(.zoom, steps: 1, speed: .nan), delta: 1, at: 0),
                      [.discrete(forward: true)])
    }

    func testScrollConversionAcceptsRepresentableLimitsAndRejectsOverflow() {
        let rotation = RotationInterpreter()
        let positiveLimit = RotationBinding(.scrollVertical, speed: Double(Int32.max) / 14)
        let negativeLimit = RotationBinding(.scrollVertical, speed: -Double(Int32.min) / 14)
        assertEffects(rotation.rotate(positiveLimit, delta: -1, at: 0),
                      [.scroll(vertical: Int32.max, horizontal: 0)])
        assertEffects(rotation.rotate(negativeLimit, delta: 1, at: 1),
                      [.scroll(vertical: Int32.min, horizontal: 0)])
        assertEffects(rotation.rotate(negativeLimit, delta: -1, at: 2), [])
        assertEffects(rotation.rotate(RotationBinding(.scrollHorizontal, speed: 1e100), delta: 1, at: 2), [])
    }

    func testAuxiliaryCountsPreserveValidSpeedsAndRejectOverflow() {
        let rotation = RotationInterpreter()
        assertEffects(rotation.rotate(RotationBinding(.volume, speed: 4), delta: -128, at: 0),
                      [.auxiliary(action: .volume, increasing: false, repeatCount: 512)])
        assertEffects(rotation.rotate(RotationBinding(.brightness, speed: 513), delta: 1, at: 1),
                      [.auxiliary(action: .brightness, increasing: true, repeatCount: 513)])
        assertEffects(rotation.rotate(RotationBinding(.volume, speed: 4.5), delta: -128, at: 2),
                      [.auxiliary(action: .volume, increasing: false, repeatCount: 640)])
        assertEffects(rotation.rotate(RotationBinding(.volume, speed: .greatestFiniteMagnitude), delta: 1, at: 3), [])
        assertEffects(rotation.rotate(RotationBinding(.volume, speed: -.infinity), delta: 1, at: 3), [])
        assertEffects(rotation.rotate(RotationBinding(.volume, speed: 1), delta: Int.min, at: 3), [])
    }

    func testRejectedAuxiliaryCountsDoNotConsumeDiscreteState() {
        for speed in [Double.greatestFiniteMagnitude, .infinity] {
            let rotation = RotationInterpreter()
            let tabs = RotationBinding(.switchTabs, steps: 3)
            assertEffects(rotation.rotate(tabs, delta: 2, at: 0), [])
            assertEffects(rotation.rotate(RotationBinding(.volume, speed: speed), delta: 1, at: 10), [])
            assertEffects(rotation.rotate(tabs, delta: 1, at: 0.1), [.discrete(forward: true)])
        }
    }

    func testExtremeThresholdsAndContinuousInterleavingPreserveExistingPolicy() {
        let rotation = RotationInterpreter()
        let extreme = RotationBinding(.zoom, steps: Int.max)
        assertEffects(rotation.rotate(extreme, delta: 127, at: 0), [])
        assertEffects(rotation.rotate(extreme, delta: -128, at: 0.1), [])
        let effects = rotation.rotate(RotationBinding(.zoom, steps: Int.min), delta: -128, at: 0.2)
        XCTAssertEqual(effects.count, 128)
        XCTAssertTrue(effects.allSatisfy { $0 == .discrete(forward: false) })

        let tabs = RotationBinding(.switchTabs, steps: 3)
        assertEffects(rotation.rotate(tabs, delta: 2, at: 1), [])
        assertEffects(rotation.rotate(RotationBinding(.volume), delta: 1, at: 1.1),
                      [.auxiliary(action: .volume, increasing: true, repeatCount: 1)])
        assertEffects(rotation.rotate(tabs, delta: 1, at: 1.2), [.discrete(forward: true)])
    }

    func testNoOpBindingAndZeroDeltaDoNotConsumeRemainderOrTiming() {
        let discrete = RotationInterpreter()
        let tabs = RotationBinding(.switchTabs, steps: 3)
        assertEffects(discrete.rotate(tabs, delta: 2, at: 0), [])
        assertEffects(discrete.rotate(RotationBinding(.none), delta: 1, at: 10), [])
        assertEffects(discrete.rotate(tabs, delta: 0, at: 10), [])
        assertEffects(discrete.rotate(tabs, delta: 1, at: 0.1), [.discrete(forward: true)])

        let scroll = RotationInterpreter()
        let vertical = RotationBinding(.scrollVertical)
        assertEffects(scroll.rotate(vertical, delta: 1, at: 0), [.scroll(vertical: -14, horizontal: 0)])
        assertEffects(scroll.rotate(vertical, delta: 0, at: 10), [])
        assertEffects(scroll.rotate(vertical, delta: 1, at: 0), [.scroll(vertical: -67, horizontal: 0)])
    }

    func testExtremeDiscreteDeltasAreLazyAndHandleReversal() {
        let binding = RotationBinding(.zoom, steps: 1, reversed: true)
        let effects = RotationInterpreter().rotate(binding, delta: Int.min, at: 0)
        XCTAssertEqual(effects.count, Int.min.magnitude)
        XCTAssertEqual(Array(effects.prefix(2)), [.discrete(forward: true), .discrete(forward: true)])
        assertEffects(RotationInterpreter().rotate(RotationBinding(.zoom, steps: Int.max),
                                                   delta: Int.min, at: 0), [.discrete(forward: false)])
    }

    func testRejectedOversizedRotationDoesNotLeaveARemainder() {
        var delivered: [RotationEffect] = []
        let queue = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                        perform: { _, effect in delivered.append(effect) })
        let rotation = RotationInterpreter()
        let binding = RotationBinding(.switchApps, steps: 3)

        XCTAssertFalse(rotation.rotate(binding, delta: 12_293, at: 0) { queue.enqueue($0, for: binding) })
        XCTAssertTrue(rotation.rotate(binding, delta: 1, at: 0.1) { queue.enqueue($0, for: binding) })
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertTrue(rotation.rotate(binding, delta: 2, at: 0.2) { queue.enqueue($0, for: binding) })
        XCTAssertEqual(delivered, [.discrete(forward: true)])
    }

    func testRejectedRotationPreservesExistingRemainderAndTiming() {
        var delivered: [RotationEffect] = []
        let queue = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                        perform: { _, effect in delivered.append(effect) })
        let rotation = RotationInterpreter()
        let tabs = RotationBinding(.switchTabs, steps: 3)
        let volume = RotationBinding(.volume, speed: 5000)

        XCTAssertTrue(rotation.rotate(tabs, delta: 2, at: 0) { queue.enqueue($0, for: tabs) })
        XCTAssertFalse(rotation.rotate(volume, delta: 1, at: 10) { queue.enqueue($0, for: volume) })
        XCTAssertTrue(rotation.rotate(tabs, delta: 1, at: 0.1) { queue.enqueue($0, for: tabs) })
        XCTAssertEqual(delivered, [.discrete(forward: true)])
    }

    func testAcceptedReentrantRotationPreservesItsRemainder() {
        let rotation = RotationInterpreter()
        let binding = RotationBinding(.switchTabs, steps: 3)
        var delivered = 0
        var queue: RotationEffectQueue!
        queue = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") }) { _, _ in
            delivered += 1
            if delivered == 1 {
                XCTAssertTrue(rotation.rotate(binding, delta: 2, at: 0.1) { queue.enqueue($0, for: binding) })
            }
        }

        XCTAssertTrue(rotation.rotate(binding, delta: 3, at: 0) { queue.enqueue($0, for: binding) })
        XCTAssertEqual(delivered, 1)
        XCTAssertTrue(rotation.rotate(binding, delta: 1, at: 0.2) { queue.enqueue($0, for: binding) })
        XCTAssertEqual(delivered, 2)
        queue = nil
    }

    private func assertEffects(_ actual: RotationEffects, _ expected: [RotationEffect], _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(actual), expected, message, file: file, line: line)
    }
}
