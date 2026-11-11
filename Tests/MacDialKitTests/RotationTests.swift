import XCTest
import MacDialKit

final class RotationTests: XCTestCase {
    func testDiscreteThresholdRemainderAndMultipleSteps() {
        let rotation = RotationInterpreter()
        let binding = RotationBinding(.switchTabs, steps: 3)
        XCTAssertEqual(rotation.rotate(binding, delta: 2, at: 0), [])
        XCTAssertEqual(rotation.rotate(binding, delta: 5, at: 0.1),
                       [.discrete(forward: true), .discrete(forward: true)])
        XCTAssertEqual(rotation.rotate(binding, delta: 2, at: 0.2), [.discrete(forward: true)])
    }

    func testDirectionChangeResetsRemainderAndReversalChangesDirection() {
        let rotation = RotationInterpreter()
        var binding = RotationBinding(.switchTabs, steps: 3)
        XCTAssertEqual(rotation.rotate(binding, delta: 2, at: 0), [])
        XCTAssertEqual(rotation.rotate(binding, delta: -2, at: 0.1), [])
        XCTAssertEqual(rotation.rotate(binding, delta: -1, at: 0.2), [.discrete(forward: false)])
        binding.reversed = true
        XCTAssertEqual(rotation.rotate(binding, delta: 3, at: 0.3), [.discrete(forward: false)])
    }

    func testPauseThresholdAndBindingChangeResetAccumulation() {
        let rotation = RotationInterpreter()
        let binding = RotationBinding(.switchTabs, steps: 3)
        XCTAssertEqual(rotation.rotate(binding, delta: 2, at: 0), [])
        XCTAssertEqual(rotation.rotate(binding, delta: 1, at: 0.8), [.discrete(forward: true)])
        XCTAssertEqual(rotation.rotate(binding, delta: 2, at: 1), [])
        XCTAssertEqual(rotation.rotate(binding, delta: 1, at: 1.801), [])
        XCTAssertEqual(rotation.rotate(RotationBinding(.mediaTracks, steps: 3), delta: 2, at: 1.9), [])
        XCTAssertEqual(rotation.rotate(RotationBinding(.mediaTracks, steps: 2), delta: 1, at: 2), [])
    }

    func testNonpositiveStepsClampAndNoOpDoesNotConsumeInput() {
        let rotation = RotationInterpreter()
        let binding = RotationBinding(.zoom, steps: 0)
        XCTAssertEqual(rotation.rotate(binding, delta: 0, at: 0), [])
        XCTAssertEqual(rotation.rotate(RotationBinding(.none), delta: 10, at: 0), [])
        XCTAssertEqual(rotation.rotate(binding, delta: -2, at: 1),
                       [.discrete(forward: false), .discrete(forward: false)])
    }

    func testScrollAccelerationSpeedAxisAndReversal() {
        let rotation = RotationInterpreter()
        let vertical = RotationBinding(.scrollVertical)
        XCTAssertEqual(rotation.rotate(vertical, delta: 1, at: 0), [.scroll(vertical: -14, horizontal: 0)])
        XCTAssertEqual(rotation.rotate(vertical, delta: 1, at: 0.03), [.scroll(vertical: -56, horizontal: 0)])
        let horizontal = RotationBinding(.scrollHorizontal, reversed: true, speed: 2)
        XCTAssertEqual(rotation.rotate(horizontal, delta: 2, at: 1), [.scroll(vertical: 0, horizontal: 56)])
    }

    func testVolumeAndBrightnessUseDirectionMagnitudeAndRoundedSpeed() {
        let rotation = RotationInterpreter()
        XCTAssertEqual(rotation.rotate(RotationBinding(.volume, speed: 1.6), delta: -3, at: 0),
                       [.auxiliary(action: .volume, increasing: false, repeatCount: 6)])
        XCTAssertEqual(rotation.rotate(RotationBinding(.brightness, reversed: true, speed: 0.2), delta: -2, at: 0.1),
                       [.auxiliary(action: .brightness, increasing: true, repeatCount: 2)])
    }
}
