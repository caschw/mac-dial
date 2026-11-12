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

    func testSynchronousZeroDelayDoesNotLeaveCompletedGesturesPending() {
        final class CompletedGesture: ScheduledGesture {
            private(set) var cancelled = false
            func cancel() { cancelled = true }
        }
        final class ImmediateScheduler: GestureScheduler {
            var now: TimeInterval { 0 }
            private(set) var gestures: [CompletedGesture] = []

            func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ScheduledGesture {
                XCTAssertEqual(interval, 0)
                let gesture = CompletedGesture()
                gestures.append(gesture)
                action()
                return gesture
            }
        }

        let settings = TestConfiguration()
        settings.config.doubleClickInterval = 0
        settings.config.longPressDuration = 0
        settings.config.modes[0].click = ClickBinding(.playPause)
        settings.config.modes[0].doubleClick = ClickBinding(.mute)
        settings.config.modes[0].longPress = ClickBinding(.none)
        let actions = RecordingActions()
        let scheduler = ImmediateScheduler()
        let interpreter = GestureInterpreter(configuration: { settings.config }, scheduler: scheduler,
                                             actions: actions, menu: RecordingMenu(), buzz: {})

        for _ in 0..<2 {
            interpreter.buttonDown()
            interpreter.buttonUp()
        }
        XCTAssertEqual(actions.performed.map(\.action), [.playPause, .playPause])

        settings.config.modes[0].longPress = ClickBinding(.nextTrack)
        interpreter.buttonDown()
        interpreter.buttonUp()
        XCTAssertEqual(actions.performed.map(\.action), [.playPause, .playPause, .nextTrack])
        XCTAssertTrue(scheduler.gestures.allSatisfy { !$0.cancelled })
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

    func testTicksDecodeAtBothBoundariesAndClampExtremeIntegers() throws {
        let cases: [(Int, Int)] = [
            (Int.min, 4), (3, 4), (4, 4), (120, 120), (121, 120), (Int.max, 120)
        ]
        for (input, expected) in cases {
            let data = Data("{\"stepsPerRevolution\":\(input)}".utf8)
            let config = try JSONDecoder().decode(DialConfig.self, from: data)
            XCTAssertEqual(config.stepsPerRevolution, expected, "input \(input)")
        }
    }

    func testShortcutIntegerLimitsRoundTripAndInvalidNestedValuesKeepArrayFallback() throws {
        var config = DialConfig()
        config.modes[0].rotate.clockwise = KeyShortcut(keyCode: .max, modifiers: .max, keyName: "Example")
        let encoded = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(DialConfig.self, from: encoded), config)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(json.contains("\"keyCode\":65535"))

        for invalid in [-1, 65536] {
            let malformed = json.replacingOccurrences(of: "\"keyCode\":65535", with: "\"keyCode\":\(invalid)")
            let decoded = try JSONDecoder().decode(DialConfig.self, from: Data(malformed.utf8))
            XCTAssertEqual(decoded.modes.map(\.name), DialMode.defaults.map(\.name))
            XCTAssertNil(decoded.modes[0].rotate.clockwise)
        }
    }

    func testNonconformingAndNegativeDurationsRetainDecodedValues() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let data = Data("""
        {"doubleClickInterval":"NaN","longPressDuration":"-Infinity"}
        """.utf8)
        let config = try decoder.decode(DialConfig.self, from: data)
        XCTAssertTrue(config.doubleClickInterval.isNaN)
        XCTAssertEqual(config.longPressDuration, -.infinity)
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let roundTrip = try decoder.decode(DialConfig.self, from: encoder.encode(config))
        XCTAssertTrue(roundTrip.doubleClickInterval.isNaN)
        XCTAssertEqual(roundTrip.longPressDuration, -.infinity)

        let negative = try JSONDecoder().decode(DialConfig.self, from: Data("""
        {"doubleClickInterval":-1,"longPressDuration":-2}
        """.utf8))
        XCTAssertEqual(negative.doubleClickInterval, -1)
        XCTAssertEqual(negative.longPressDuration, -2)
    }

    func testInvalidPersistedTimingsAndSpeedsAreHandledAtUseTime() throws {
        var stored = DialConfig()
        stored.doubleClickInterval = -1
        stored.longPressDuration = -2
        stored.modes[0].rotate = RotationBinding(.scrollVertical, speed: -1)
        let decoded = try JSONDecoder().decode(DialConfig.self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(decoded, stored)
        XCTAssertEqual(Array(RotationInterpreter().rotate(decoded.modes[0].rotate, delta: 1, at: 0)), [])

        let click = makeController(doubleClick: .mute)
        click.settings.config.doubleClickInterval = decoded.doubleClickInterval
        click.device.onButton?(.pressed)
        click.device.onButton?(.released)
        click.clock.advance(by: DialConfig.defaultDoubleClickInterval)
        XCTAssertEqual(click.actions.performed.map(\.action), [.playPause])

        let hold = makeController()
        hold.settings.config.longPressDuration = decoded.longPressDuration
        hold.device.onButton?(.pressed)
        hold.clock.advance(by: DialConfig.defaultLongPressDuration)
        hold.device.onButton?(.released)
        XCTAssertEqual(hold.actions.performed.map(\.action), [.nextTrack])
    }

    func testMalformedRootFailsRatherThanInventingAConfiguration() {
        for json in ["[]", "null", "{", "\"text\""] {
            XCTAssertThrowsError(try JSONDecoder().decode(DialConfig.self, from: Data(json.utf8)), json)
        }
    }

    func testUnknownSelectionRetainsIdentifierAndUsesFirstModeFallback() {
        var config = DialConfig()
        config.modes = [DialMode(name: "A", icon: "star"), DialMode(name: "B", icon: "star")]
        let unknown = UUID()
        config.selectMode(unknown)
        XCTAssertEqual(config.currentModeID, unknown)
        XCTAssertEqual(config.currentMode.id, config.modes[0].id)
        config.selectNextMode()
        XCTAssertEqual(config.currentMode.id, config.modes[1].id)
    }

    func testInvalidGestureIntervalsUseDefaultsWithoutChangingStoredValues() {
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            let click = makeController(doubleClick: .mute)
            click.settings.config.doubleClickInterval = invalid
            click.device.onButton?(.pressed)
            click.device.onButton?(.released)
            click.clock.advance(by: 0.299)
            XCTAssertTrue(click.actions.performed.isEmpty)
            click.clock.advance(by: 0.001)
            XCTAssertEqual(click.actions.performed.map(\.action), [.playPause])
            if invalid.isNaN {
                XCTAssertTrue(click.settings.config.doubleClickInterval.isNaN)
            } else {
                XCTAssertEqual(click.settings.config.doubleClickInterval, invalid)
            }

            let hold = makeController()
            hold.settings.config.longPressDuration = invalid
            hold.device.onButton?(.pressed)
            hold.clock.advance(by: 0.499)
            XCTAssertTrue(hold.actions.performed.isEmpty)
            hold.clock.advance(by: 0.001)
            hold.device.onButton?(.released)
            XCTAssertEqual(hold.actions.performed.map(\.action), [.nextTrack])
        }
    }

    func testZeroAndPositiveIntervalsOutsideEditorRangeRemainUsable() {
        let click = makeController(doubleClick: .mute)
        click.settings.config.doubleClickInterval = 0
        click.device.onButton?(.pressed)
        click.device.onButton?(.released)
        XCTAssertTrue(click.actions.performed.isEmpty)
        click.clock.advance(by: 0)
        XCTAssertEqual(click.actions.performed.map(\.action), [.playPause])

        let immediateHold = makeController()
        immediateHold.settings.config.longPressDuration = 0
        immediateHold.device.onButton?(.pressed)
        immediateHold.clock.advance(by: 0)
        immediateHold.device.onButton?(.released)
        XCTAssertEqual(immediateHold.actions.performed.map(\.action), [.nextTrack])

        let slowHold = makeController()
        slowHold.settings.config.longPressDuration = 2
        slowHold.device.onButton?(.pressed)
        slowHold.clock.advance(by: 1.99)
        XCTAssertTrue(slowHold.actions.performed.isEmpty)
        slowHold.clock.advance(by: 0.01)
        XCTAssertEqual(slowHold.actions.performed.map(\.action), [.nextTrack])
    }

    func testEverySignedReportDeltaIsForwardedExceptZero() {
        let controller = makeController()
        for delta in Int(Int8.min)...Int(Int8.max) {
            controller.device.onRotate?(delta)
        }
        let expected = Array(Int(Int8.min)...(-1)) + Array(1...Int(Int8.max))
        XCTAssertEqual(controller.actions.rotations.map(\.1), expected)
        XCTAssertTrue(controller.actions.performed.isEmpty)
    }

    func testZeroRotationDoesNotCancelHoldOrSuppressRelease() {
        let controller = makeController()
        controller.device.onButton?(.pressed)
        controller.clock.advance(by: 0.2)
        controller.device.onRotate?(0)
        controller.clock.advance(by: 0.3)
        controller.device.onButton?(.released)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.nextTrack])
        XCTAssertTrue(controller.actions.rotations.isEmpty)
        XCTAssertEqual(controller.buzzes, 1)
    }

    func testAggregateRotationCancelsHoldAndSuppressesClick() {
        for delta in [Int.min, -129, 128, Int.max] {
            let controller = makeController()
            controller.device.onButton?(.pressed)
            controller.device.onRotate?(delta)
            controller.device.onButton?(.released)
            controller.clock.advance(by: 1)
            XCTAssertTrue(controller.actions.performed.isEmpty, "delta \(delta)")
            XCTAssertEqual(controller.actions.rotations.map(\.1), [delta])
        }
    }

    func testZeroMenuRotationDoesNotMoveAndAggregateDeltasAreForwarded() {
        let controller = makeController()
        controller.radial.isVisible = true
        controller.settings.config.detentHaptics = false
        controller.device.onRotate?(0)
        XCTAssertTrue(controller.radial.moves.isEmpty)
        XCTAssertEqual(controller.buzzes, 0)
        for delta in [Int.min, -129, -128, 127, 128, Int.max] { controller.device.onRotate?(delta) }
        XCTAssertEqual(controller.radial.moves, [Int.min, -129, -128, 127, 128, Int.max])
        XCTAssertEqual(controller.buzzes, 6)
    }

    func testDuplicatePressDoesNotRestartHoldOrDuplicateMouseDown() {
        let controller = makeController()
        controller.device.onButton?(.pressed)
        controller.clock.advance(by: 0.2)
        controller.device.onButton?(.pressed)
        controller.clock.advance(by: 0.3)
        controller.device.onButton?(.released)
        XCTAssertEqual(controller.actions.performed.map(\.action), [.nextTrack])
        XCTAssertEqual(controller.buzzes, 1)

        let drag = makeController(click: .leftClick, longPress: .none)
        drag.device.onButton?(.pressed)
        drag.device.onButton?(.pressed)
        drag.device.onButton?(.released)
        XCTAssertEqual(drag.actions.mouseEvents.map(\.1), [true, false])
    }

    func testDuplicatePressCannotUndoAppSwitchReleaseSuppression() {
        let controller = makeController()
        controller.actions.switchPending = true
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.pressed)
        controller.device.onButton?(.released)
        controller.clock.advance(by: 1)
        XCTAssertTrue(controller.actions.performed.isEmpty)
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
