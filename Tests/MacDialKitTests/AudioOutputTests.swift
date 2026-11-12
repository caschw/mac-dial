import XCTest
import MacDialKit

final class AudioOutputTests: XCTestCase {
    private let speakers = AudioOutput(uid: "built-in", name: "Speakers", supportsVolume: true)
    private let headphones = AudioOutput(uid: "headphones", name: "Speakers", supportsVolume: true)
    private let hdmi = AudioOutput(uid: "hdmi", name: "Display", supportsVolume: false)

    func testHiddenOutputsSurviveDisconnectionAndNewOutputsAppear() throws {
        var preferences = AudioOutputPreferences()
        preferences.selectedUID = headphones.uid
        preferences.disable(headphones)
        preferences.disable(headphones)
        XCTAssertEqual(preferences.disabled.count, 1)
        XCTAssertEqual(preferences.eligibleOutputs([speakers, headphones, hdmi]), [speakers])
        preferences = try JSONDecoder().decode(AudioOutputPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(preferences.disabled.first?.name, headphones.name)
        XCTAssertEqual(preferences.effectiveUID(outputs: [speakers], defaultUID: speakers.uid), speakers.uid)
        XCTAssertEqual(preferences.selectedUID, headphones.uid)
        XCTAssertEqual(preferences.effectiveUID(outputs: [speakers, headphones], defaultUID: speakers.uid), headphones.uid)
        XCTAssertEqual(preferences.eligibleOutputs([headphones, speakers]), [speakers])
        preferences.enable(headphones.uid)
        XCTAssertEqual(preferences.eligibleOutputs([headphones, speakers]), [headphones, speakers])
        XCTAssertNil(preferences.effectiveUID(outputs: [], defaultUID: nil))
    }

    func testInvalidAndDuplicateIdentitiesDoNotBecomeArcChoices() {
        var preferences = AudioOutputPreferences()
        let invalid = AudioOutput(uid: "", name: "", supportsVolume: true)
        preferences.disable(invalid)
        XCTAssertTrue(preferences.disabled.isEmpty)
        XCTAssertEqual(preferences.eligibleOutputs([invalid, speakers, speakers, hdmi, headphones]), [speakers, headphones])
        preferences.enable("unknown")
        XCTAssertTrue(preferences.disabled.isEmpty)
        XCTAssertEqual(preferences.effectiveUID(outputs: [speakers], defaultUID: speakers.uid), speakers.uid)
    }

    func testMalformedPreferenceRecordsAreRejected() {
        for json in [
            #"{"selectedUID":""}"#,
            #"{"selectedUID":42}"#,
            #"{"disabled":[{"uid":"","name":"Output"}]}"#,
            #"{"disabled":[{"uid":"same","name":"A"},{"uid":"same","name":"B"}]}"#,
            #"{"disabled":"invalid"}"#
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(AudioOutputPreferences.self, from: Data(json.utf8)))
        }
    }

    func testMigrationPreservesLegacyModesAndRespectsDeletion() throws {
        var legacy = DialConfig()
        legacy.modes = [DialMode(name: "Custom", icon: "star.fill", rotate: RotationBinding(.volume, speed: 3))]
        legacy.currentModeID = legacy.modes[0].id
        legacy.stepsPerRevolution = 45
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        document.removeValue(forKey: "volumeOutputModeIntroduced")
        document.removeValue(forKey: "audioOutput")
        let oldModes = legacy.modes
        var decoded = try JSONDecoder().decode(DialConfig.self, from: JSONSerialization.data(withJSONObject: document))
        decoded.introduceVolumeOutputMode()
        XCTAssertEqual(Array(decoded.modes.prefix(oldModes.count)), oldModes)
        XCTAssertEqual(decoded.currentModeID, legacy.currentModeID)
        XCTAssertEqual(decoded.stepsPerRevolution, 45)
        XCTAssertEqual(decoded.modes.last?.kind, .volumeOutput)
        let migrated = decoded
        decoded.introduceVolumeOutputMode()
        XCTAssertEqual(decoded, migrated)
        decoded.modes.removeAll { $0.kind == .volumeOutput }
        decoded = try JSONDecoder().decode(DialConfig.self, from: JSONEncoder().encode(decoded))
        decoded.introduceVolumeOutputMode()
        XCTAssertEqual(decoded.modes, oldModes)
    }

    func testVolumeStepsAndBalanceAtBoundaries() throws {
        XCTAssertEqual(try AudioVolume.adjusted([0], increasing: true, repeatCount: 1), [1.0 / 64])
        XCTAssertEqual(try AudioVolume.adjusted([1], increasing: true, repeatCount: 1), [1])
        XCTAssertEqual(try AudioVolume.adjusted([0], increasing: false, repeatCount: 1), [0])
        XCTAssertEqual(try AudioVolume.adjusted([1], increasing: false, repeatCount: 1), [63.0 / 64])
        XCTAssertEqual(try AudioVolume.adjusted([63.0 / 64], increasing: true, repeatCount: 2), [1])
        XCTAssertEqual(try AudioVolume.adjusted([1.0 / 64], increasing: false, repeatCount: 2), [0])
        XCTAssertEqual(try AudioVolume.adjusted([0.5, 0.25], increasing: true, repeatCount: 16), [0.75, 0.375])
        XCTAssertEqual(try AudioVolume.adjusted([0.5, 0.25], increasing: false, repeatCount: 16), [0.25, 0.125])
        XCTAssertEqual(try AudioVolume.adjusted([0, 0], increasing: true, repeatCount: 4), [0.0625, 0.0625])
        XCTAssertEqual(try AudioVolume.adjusted([0.5, 0], increasing: true, repeatCount: Int.max), [1, 0])
        XCTAssertEqual(try AudioVolume.adjusted([0.5], increasing: false, repeatCount: Int.max), [0])
        for levels: [Float] in [[], [.nan], [.infinity], [-.infinity], [-Float.leastNonzeroMagnitude], [Float(1).nextUp]] {
            XCTAssertThrowsError(try AudioVolume.adjusted(levels, increasing: true, repeatCount: 1))
        }
        for count in [0, -1, Int.min] {
            XCTAssertThrowsError(try AudioVolume.adjusted([0.5], increasing: true, repeatCount: count))
        }
    }

    func testLiveArcRefreshRetainsSelectionAndRemovesStaleChoice() throws {
        let mode = DialMode.volumeOutput
        let preferences = AudioOutputPreferences()
        var navigation = try RadialMenuNavigation(
            items: AudioOutputMenu.items(modes: [mode], outputs: [speakers, headphones], preferences: preferences),
            selectedID: mode.id.uuidString, detentsPerItem: 2)
        _ = navigation.confirm()
        let headphoneID = "\(mode.id.uuidString).output.\(headphones.uid)"
        XCTAssertTrue(navigation.selectItem(id: headphoneID))
        XCTAssertFalse(navigation.move(by: 1))
        try navigation.replaceItems(AudioOutputMenu.items(modes: [mode], outputs: [hdmi, headphones, speakers],
                                                         preferences: preferences))
        XCTAssertEqual(navigation.current.selectedSlot.item?.id, headphoneID)
        XCTAssertFalse(navigation.move(by: 1))
        try navigation.replaceItems(AudioOutputMenu.items(modes: [mode], outputs: [speakers], preferences: preferences))
        XCTAssertNil(navigation.current.selectedSlot.item)
        if case .returned = navigation.confirm() {} else { XCTFail("Removed output should select Back") }
        XCTAssertEqual(navigation.depth, 0)
    }

    func testUtilitySelectionPreservesThePreviousOperatingMode() {
        var config = DialConfig()
        let previous = config.modes[1]
        let utility = config.modes.first { $0.kind == .volumeOutput }!
        config.selectMode(previous.id)
        config.selectMode(utility.id)
        XCTAssertEqual(config.currentModeID, previous.id)
        XCTAssertEqual(config.currentMode, previous)
        config.audioOutput.selectedUID = speakers.uid
        config.selectMode(utility.id)
        XCTAssertEqual(config.currentModeID, previous.id)
        config.selectMode(config.modes[0].id)
        XCTAssertEqual(config.currentModeID, config.modes[0].id)
    }

    func testCyclingContinuesAfterAUtilityWithoutChangingTheWorkingMode() {
        var config = DialConfig()
        let utility = config.modes.first { $0.kind == .volumeOutput }!
        let ordinary = config.enabledModes.last { $0.kind == nil }!
        config.selectMode(ordinary.id)
        var candidate = config
        candidate.selectNextMode()
        XCTAssertEqual(candidate.currentModeID, utility.id)
        config.selectMode(utility.id)
        XCTAssertEqual(config.currentModeID, ordinary.id)
        candidate = config
        candidate.selectNextMode(after: utility.id)
        XCTAssertEqual(candidate.currentModeID, config.enabledModes.first?.id)
        candidate = config
        candidate.selectNextMode(after: UUID())
        XCTAssertEqual(candidate.currentModeID, utility.id, "A missing cycling cursor falls back to the working mode")
        config.modes.removeAll { $0.kind != nil }
        candidate = config
        candidate.selectNextMode(after: utility.id)
        XCTAssertEqual(candidate.currentModeID, config.enabledModes.first?.id)
    }

    func testEmptyArcAndConfirmationHaveTypedPayloads() throws {
        let mode = DialMode.volumeOutput
        var navigation = try RadialMenuNavigation(
            items: AudioOutputMenu.items(modes: [mode], outputs: [hdmi], preferences: AudioOutputPreferences()),
            selectedID: nil, detentsPerItem: 1)
        _ = navigation.confirm()
        if case .selectedLeaf(let item) = navigation.confirm(),
           case .leaf(.information) = item.content {} else { XCTFail("Empty arc should be informational") }
        try navigation.replaceItems(AudioOutputMenu.items(modes: [mode], outputs: [speakers],
                                                         preferences: AudioOutputPreferences()))
        XCTAssertTrue(navigation.selectItem(id: "\(mode.id.uuidString).output.\(speakers.uid)"))
        if case .selectedLeaf(let item) = navigation.confirm(),
           case .leaf(.audioOutput(let uid)) = item.content {
            XCTAssertEqual(uid, speakers.uid)
        } else { XCTFail("Output should carry its stable UID") }
        XCTAssertFalse(navigation.selectItem(id: "missing"))
        let before = navigation.current.selectedSlot.item?.id
        XCTAssertThrowsError(try navigation.replaceItems([]))
        XCTAssertEqual(navigation.current.selectedSlot.item?.id, before)
    }
}
