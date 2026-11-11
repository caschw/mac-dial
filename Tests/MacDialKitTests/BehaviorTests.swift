import XCTest

final class BehaviorTests: XCTestCase {
    func testMissingAndInvalidSettingsUseCompatibleDefaults() throws {
        let config = try JSONDecoder().decode(DialConfig.self, from: Data("""
        {"stepsPerRevolution":999,"menuBarGlyph":"future","fastWake":"invalid","futureKey":true}
        """.utf8))
        XCTAssertEqual(config.stepsPerRevolution, 120)
        XCTAssertEqual(config.menuBarGlyph, .twoTone)
        XCTAssertTrue(config.fastWake)
        XCTAssertEqual(config.doubleClickInterval, 0.3)
        XCTAssertEqual(config.longPressDuration, 0.5)
        XCTAssertEqual(config.modes.map(\.name), DialMode.defaults.map(\.name))
    }

    func testSettingsRoundTripPreservesBindingsAndIdentifiers() throws {
        var config = DialConfig()
        config.currentModeID = config.modes[1].id
        config.modes[0].rotate = RotationBinding(.customShortcut, steps: 7, reversed: true,
                                                speed: 2, clockwise: .make(12, "Q", .command))
        config.modes[0].click = ClickBinding(.openApp, appPath: "/Applications/Example.app")
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(DialConfig.self, from: data), config)
    }

    func testMalformedModesFallBackAndTicksClampAtLowerBound() throws {
        let config = try JSONDecoder().decode(DialConfig.self, from: Data("""
        {"modes":[{"name":"incomplete"}],"stepsPerRevolution":-1}
        """.utf8))
        XCTAssertEqual(config.stepsPerRevolution, 4)
        XCTAssertEqual(config.modes.map(\.name), DialMode.defaults.map(\.name))
    }

    func testCurrentModeFallsBackToFirstEvenIfDisabled() {
        var config = DialConfig()
        config.modes[0].enabled = false
        config.currentModeID = UUID()
        XCTAssertEqual(config.currentMode, config.modes[0])
        config.modes = []
        XCTAssertEqual(config.currentMode.name, "Scroll")
    }

    func testClickIsImmediateWithoutDoubleClickBinding() {
        let controller = makeController()
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.released)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.playPause])
    }

    func testDoubleClickSuppressesSingleClick() {
        let controller = makeController(doubleClick: .mute)
        for _ in 0..<2 {
            controller.device.onButton?(.pressed)
            controller.device.onButton?(.released)
        }
        XCTAssertEqual(controller.actions.performed.map(\.action), [.mute])
    }

    func testPressedRotationSuppressesClickAndUsesPressedBinding() {
        let controller = makeController()
        controller.device.onButton?(.pressed)
        controller.device.onRotate?(2)
        controller.device.onButton?(.released)
        XCTAssertTrue(controller.actions.performed.isEmpty)
        XCTAssertEqual(controller.actions.rotations.map(\.0.action), [.brightness])
        XCTAssertEqual(controller.actions.rotations.map(\.1), [2])
    }

    func testMouseOnlyModePassesThroughDownAndUpForDragging() {
        let controller = makeController(click: .leftClick, longPress: .none)
        controller.device.onButton?(.pressed)
        controller.device.onRotate?(-1)
        controller.device.onButton?(.released)
        XCTAssertEqual(controller.actions.mouseEvents.map(\.0), [.leftClick, .leftClick])
        XCTAssertEqual(controller.actions.mouseEvents.map(\.1), [true, false])
        XCTAssertTrue(controller.actions.performed.isEmpty)
    }

    func testAppSwitchCommitSwallowsRelease() {
        let controller = makeController()
        controller.actions.switchPending = true
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.released)
        XCTAssertTrue(controller.actions.performed.isEmpty)
        XCTAssertFalse(controller.actions.switchPending)
    }

    func testMenuRotationAndConfirmationDoNotDispatchBindings() {
        let controller = makeController()
        controller.radial.isVisible = true
        controller.device.onRotate?(3)
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.released)
        XCTAssertEqual(controller.radial.moves, [3])
        XCTAssertEqual(controller.radial.confirmations, 1)
        XCTAssertTrue(controller.actions.rotations.isEmpty)
        XCTAssertTrue(controller.actions.performed.isEmpty)
    }

    func testLongPressSuppressesRelease() {
        let controller = makeController()
        controller.settings.config.longPressDuration = 0.01
        controller.device.onButton?(.pressed)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        controller.device.onButton?(.released)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.nextTrack])
    }

    private func makeController(click: ClickAction = .playPause, doubleClick: ClickAction = .none,
                                longPress: ClickAction = .nextTrack) -> DialController {
        let settings = SettingsStore()
        settings.config.modes = [
            DialMode(name: "Test", icon: "star", rotate: RotationBinding(.volume),
                     pressedRotate: RotationBinding(longPress == .none ? .none : .brightness),
                     click: ClickBinding(click), doubleClick: ClickBinding(doubleClick),
                     longPress: ClickBinding(longPress))
        ]
        return DialController(device: DialDevice(), settings: settings)
    }
}
