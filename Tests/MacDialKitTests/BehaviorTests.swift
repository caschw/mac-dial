import XCTest
import MacDialKit

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
                                                speed: 2, clockwise: KeyShortcut(keyCode: 12, modifiers: 1 << 20, keyName: "Q"))
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
        controller.device.onButton?(.pressed)
        controller.clock.advance(by: 0.5)
        controller.device.onButton?(.released)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.nextTrack])
    }

    func testSingleClickWaitsForConfiguredDoubleClickDeadline() {
        let controller = makeController(doubleClick: .mute)
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.released)
        controller.clock.advance(by: 0.299)
        XCTAssertTrue(controller.actions.performed.isEmpty)
        controller.clock.advance(by: 0.001)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.playPause])
        controller.clock.advance(by: 1)
        XCTAssertEqual(controller.actions.performed.count, 1)
    }

    func testSecondClickJustBeforeDeadlineCancelsPendingSingleClick() {
        let controller = makeController(doubleClick: .mute)
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.released)
        controller.clock.advance(by: 0.299)
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.released)
        controller.clock.advance(by: 1)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.mute])
    }

    func testClickAfterDeadlineStartsNewSingleClick() {
        let controller = makeController(doubleClick: .mute)
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.released)
        controller.clock.advance(by: 0.3)
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.released)
        controller.clock.advance(by: 0.3)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.playPause, .playPause])
    }

    func testLongPressFiresAtDeadlineOnlyOnceWithHaptic() {
        let controller = makeController()
        controller.device.onButton?(.pressed)
        controller.clock.advance(by: 0.499)
        XCTAssertTrue(controller.actions.performed.isEmpty)
        controller.clock.advance(by: 0.001)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.nextTrack])
        XCTAssertEqual(controller.buzzes, 1)
        controller.clock.advance(by: 2)
        controller.device.onButton?(.released)
        XCTAssertEqual(controller.actions.performed.count, 1)
    }

    func testReleaseBeforeHoldDeadlineCancelsLongPress() {
        let controller = makeController()
        controller.device.onButton?(.pressed)
        controller.clock.advance(by: 0.499)
        controller.device.onButton?(.released)
        controller.clock.advance(by: 1)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.playPause])
        XCTAssertEqual(controller.buzzes, 0)
    }

    func testPressedRotationCancelsLongPress() {
        let controller = makeController()
        controller.device.onButton?(.pressed)
        controller.clock.advance(by: 0.2)
        controller.device.onRotate?(-2)
        controller.clock.advance(by: 1)
        controller.device.onButton?(.released)
        XCTAssertTrue(controller.actions.performed.isEmpty)
        XCTAssertEqual(controller.buzzes, 0)
        XCTAssertEqual(controller.actions.rotations.map(\.1), [-2])
    }

    func testDisabledPressedBindingFallsBackToNormalRotation() {
        let controller = makeController(longPress: .none)
        controller.device.onButton?(.pressed)
        controller.device.onRotate?(2)
        controller.device.onButton?(.released)
        XCTAssertEqual(controller.actions.rotations.map(\.0.action), [.volume])
        XCTAssertTrue(controller.actions.performed.isEmpty)
    }

    func testUnpressedRotationUsesNormalBindingAndStrayReleaseDoesNothing() {
        let controller = makeController()
        controller.device.onButton?(.released)
        controller.device.onRotate?(-3)
        XCTAssertEqual(controller.actions.rotations.map(\.0.action), [.volume])
        XCTAssertEqual(controller.actions.rotations.map(\.1), [-3])
        XCTAssertTrue(controller.actions.performed.isEmpty)
    }

    func testMouseOnlyModesKeepOriginalButtonUntilRelease() {
        for action in [ClickAction.leftClick, .rightClick, .middleClick] {
            let controller = makeController(click: action, longPress: .none)
            controller.device.onButton?(.pressed)
            controller.clock.advance(by: 10)
            controller.settings.config.modes[0].click = ClickBinding(.playPause)
            controller.device.onButton?(.released)
            XCTAssertEqual(controller.actions.mouseEvents.map(\.0), [action, action])
            XCTAssertEqual(controller.actions.mouseEvents.map(\.1), [true, false])
            XCTAssertEqual(controller.clock.pendingCount, 0)
        }
    }

    func testMouseClickWithDoubleClickBindingIsNotPassedThrough() {
        let controller = makeController(click: .leftClick, doubleClick: .doubleLeftClick, longPress: .none)
        controller.device.onButton?(.pressed)
        XCTAssertTrue(controller.actions.mouseEvents.isEmpty)
        controller.device.onButton?(.released)
        controller.clock.advance(by: 0.3)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.leftClick])
    }

    func testMenuHoldDismissesWithoutConfirmingOrDispatching() {
        let controller = makeController()
        controller.radial.isVisible = true
        controller.device.onButton?(.pressed)
        controller.clock.advance(by: 0.5)
        controller.device.onButton?(.released)
        XCTAssertEqual(controller.radial.dismissals, 1)
        XCTAssertEqual(controller.radial.confirmations, 0)
        XCTAssertTrue(controller.actions.performed.isEmpty)
        XCTAssertEqual(controller.buzzes, 0)
    }

    func testMenuHapticsOnlyWhenSelectionChangesWithoutHardwareDetents() {
        let controller = makeController()
        controller.radial.isVisible = true
        controller.settings.config.detentHaptics = false
        controller.device.onRotate?(1)
        XCTAssertEqual(controller.buzzes, 1)
        controller.radial.selectionChanged = false
        controller.device.onRotate?(1)
        XCTAssertEqual(controller.buzzes, 1)
        controller.radial.selectionChanged = true
        controller.settings.config.detentHaptics = true
        controller.device.onRotate?(1)
        XCTAssertEqual(controller.buzzes, 1)
        controller.settings.config.detentHaptics = false
        controller.settings.config.menuHaptics = false
        controller.device.onRotate?(1)
        XCTAssertEqual(controller.buzzes, 1)
    }

    func testLongPressDoesNotDuplicateMenuHapticOrIgnoreHapticSetting() {
        for action in [ClickAction.radialMenu, .nextTrack] {
            let controller = makeController(longPress: action)
            if action != .radialMenu { controller.settings.config.menuHaptics = false }
            controller.device.onButton?(.pressed)
            controller.clock.advance(by: 0.5)
            XCTAssertEqual(controller.actions.performed.map(\.action), [action])
            XCTAssertEqual(controller.buzzes, 0)
        }
    }

    func testModeChangeResetCancelsPendingSingleClickAndHold() {
        let controller = makeController(doubleClick: .mute)
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.released)
        controller.device.onButton?(.pressed)
        XCTAssertEqual(controller.clock.pendingCount, 2)
        controller.settings.config.modes.append(DialMode(name: "New", icon: "star"))
        controller.settings.config.selectMode(controller.settings.config.modes[1].id)
        controller.gestures.resetGesture()
        controller.clock.advance(by: 1)
        XCTAssertTrue(controller.actions.performed.isEmpty)
        XCTAssertEqual(controller.clock.pendingCount, 0)
    }

    func testPendingClickUsesUpdatedBindingWithinSameMode() {
        let controller = makeController(doubleClick: .mute)
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.released)
        controller.settings.config.modes[0].click = ClickBinding(.nextMode)
        controller.clock.advance(by: 0.3)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.nextMode])
    }

    func testDestroyingInterpreterCancelsPendingTimers() {
        let clock = TestClock()
        let actions = RecordingActions()
        let menu = RecordingMenu()
        var config = DialConfig()
        config.modes[0].doubleClick = ClickBinding(.mute)
        var interpreter: GestureInterpreter? = GestureInterpreter(configuration: { config }, scheduler: clock,
                                                                  actions: actions, menu: menu, buzz: {})
        interpreter?.buttonDown()
        interpreter?.buttonUp()
        interpreter?.buttonDown()
        XCTAssertEqual(clock.pendingCount, 2)
        interpreter = nil
        XCTAssertEqual(clock.pendingCount, 0)
        clock.advance(by: 1)
        XCTAssertTrue(actions.performed.isEmpty)
    }

    func testModeCyclingSkipsDisabledModesAndWraps() {
        var config = DialConfig()
        config.modes = [
            DialMode(name: "A", icon: "star"),
            DialMode(name: "Disabled", icon: "star", enabled: false),
            DialMode(name: "B", icon: "star")
        ]
        config.selectMode(config.modes[0].id)
        config.selectNextMode()
        XCTAssertEqual(config.currentMode.id, config.modes[2].id)
        config.selectNextMode()
        XCTAssertEqual(config.currentMode.id, config.modes[0].id)
        config.selectMode(config.modes[1].id)
        config.selectNextMode()
        XCTAssertEqual(config.currentMode.id, config.modes[0].id)
    }

    func testModeCyclingWithNoEnabledOrNoModesLeavesSelectionUnchanged() {
        var config = DialConfig()
        config.currentModeID = config.modes[0].id
        for index in config.modes.indices { config.modes[index].enabled = false }
        let selected = config.currentModeID
        config.selectNextMode()
        XCTAssertEqual(config.currentModeID, selected)
        config.modes = []
        config.selectNextMode()
        XCTAssertEqual(config.currentModeID, selected)
    }

    func testLegacyExportDecodesWithoutNewerKeysAndReencodesOriginalSchema() throws {
        let id = try XCTUnwrap(UUID(uuidString: "B166CB73-4372-42CF-BDE3-20710EFB9B88"))
        let legacy = Data("""
        {
          "modes": [{
            "id": "B166CB73-4372-42CF-BDE3-20710EFB9B88", "name": "Legacy", "icon": "keyboard", "enabled": true,
            "rotate": {"action":"customShortcut","stepsPerAction":2,"reversed":true,"speed":1.5,
                       "clockwise":{"keyCode":12,"modifiers":1048576,"keyName":"Q"}},
            "pressedRotate": {"action":"switchApps","stepsPerAction":4,"reversed":false,"speed":1},
            "click": {"action":"openApp","appPath":"/Applications/Example.app"},
            "doubleClick": {"action":"none"},
            "longPress": {"action":"radialMenu"}
          }],
          "currentModeID":"B166CB73-4372-42CF-BDE3-20710EFB9B88",
          "stepsPerRevolution":48, "detentHaptics":false, "menuHaptics":false, "showHUD":false,
          "doubleClickInterval":0.4, "longPressDuration":0.7
        }
        """.utf8)
        let config = try JSONDecoder().decode(DialConfig.self, from: legacy)
        XCTAssertEqual(config.currentModeID, id)
        XCTAssertEqual(config.currentMode.name, "Legacy")
        XCTAssertEqual(config.currentMode.rotate,
                       RotationBinding(.customShortcut, steps: 2, reversed: true, speed: 1.5,
                                       clockwise: KeyShortcut(keyCode: 12, modifiers: 1 << 20, keyName: "Q")))
        XCTAssertEqual(config.currentMode.pressedRotate.action, .switchApps)
        XCTAssertEqual(config.currentMode.click.appPath, "/Applications/Example.app")
        XCTAssertEqual(config.currentMode.longPress.action, .radialMenu)
        XCTAssertEqual(config.stepsPerRevolution, 48)
        XCTAssertFalse(config.detentHaptics)
        XCTAssertFalse(config.menuHaptics)
        XCTAssertFalse(config.showHUD)
        XCTAssertEqual(config.doubleClickInterval, 0.4)
        XCTAssertEqual(config.longPressDuration, 0.7)
        XCTAssertTrue(config.fastWake)
        XCTAssertTrue(config.radialAtCursor)
        XCTAssertEqual(config.menuBarGlyph, .twoTone)
        let encoded = try JSONEncoder().encode(config)
        let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        for (key, value) in original {
            XCTAssertEqual(actual[key] as? NSObject, value as? NSObject, key)
        }
        XCTAssertEqual(try JSONDecoder().decode(DialConfig.self, from: encoded), config)
    }

    func testUnknownActionInSavedModesPreservesWholeArrayFallback() throws {
        var config = DialConfig()
        let encoded = try JSONEncoder().encode(config)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
            .replacingOccurrences(of: "\"scrollVertical\"", with: "\"futureAction\"")
        config = try JSONDecoder().decode(DialConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.modes.map(\.name), DialMode.defaults.map(\.name))
        XCTAssertEqual(config.modes[0].rotate.action, .scrollVertical)
    }

    func testExplicitEmptyModesAndInvalidIdentifierKeepExistingFallbackBehavior() throws {
        let config = try JSONDecoder().decode(DialConfig.self, from: Data("""
        {"modes":[],"currentModeID":"invalid","stepsPerRevolution":"invalid"}
        """.utf8))
        XCTAssertTrue(config.modes.isEmpty)
        XCTAssertNil(config.currentModeID)
        XCTAssertEqual(config.currentMode.name, "Scroll")
        XCTAssertEqual(config.stepsPerRevolution, 36)
    }

    private func makeController(click: ClickAction = .playPause, doubleClick: ClickAction = .none,
                                longPress: ClickAction = .nextTrack) -> GestureHarness {
        let settings = TestConfiguration()
        settings.config.modes = [
            DialMode(name: "Test", icon: "star", rotate: RotationBinding(.volume),
                     pressedRotate: RotationBinding(longPress == .none ? .none : .brightness),
                     click: ClickBinding(click), doubleClick: ClickBinding(doubleClick),
                     longPress: ClickBinding(longPress))
        ]
        return GestureHarness(settings: settings)
    }
}
