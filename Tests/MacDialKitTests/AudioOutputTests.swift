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

    func testSystemDefaultAndDeviceConfirmationHaveDistinctTypedPayloads() throws {
        let mode = DialMode.volumeOutput
        var navigation = try RadialMenuNavigation(
            items: AudioOutputMenu.items(modes: [mode], outputs: [hdmi], preferences: AudioOutputPreferences()),
            selectedID: nil, detentsPerItem: 1)
        _ = navigation.confirm()
        if case .selectedLeaf(let item) = navigation.confirm(),
           case .leaf(.systemDefaultAudioOutput) = item.content {
            XCTAssertEqual(item.title, "System default")
            XCTAssertEqual(item.symbol, "hifispeaker")
        } else { XCTFail("System default must be selectable even without controllable devices") }
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

    func testSystemDefaultSurvivesHiddenOutputsDiscoveryErrorsAndLiveRefresh() throws {
        let mode = DialMode.volumeOutput
        var preferences = selecting(speakers.uid)
        preferences.disable(speakers)
        preferences.disable(headphones)
        var navigation = try RadialMenuNavigation(
            items: AudioOutputMenu.items(modes: [mode], outputs: [speakers, headphones],
                                         preferences: preferences, error: "Discovery failed"),
            selectedID: mode.id.uuidString, detentsPerItem: 1)
        _ = navigation.confirm()
        let id = "\(mode.id.uuidString).system-default"
        XCTAssertTrue(navigation.selectItem(id: id))
        XCTAssertEqual(navigation.current.slots.compactMap(\.item).map(\.title),
                       ["System default", "Discovery failed"])
        try navigation.replaceItems(AudioOutputMenu.items(modes: [mode], outputs: [],
                                                         preferences: preferences))
        XCTAssertEqual(navigation.current.selectedSlot.item?.id, id)
        if case .selectedLeaf(let item) = navigation.confirm(),
           case .leaf(.systemDefaultAudioOutput) = item.content {} else {
            XCTFail("Discovery failure and hidden devices must not remove System default")
        }
        preferences.selectedUID = nil
        preferences = try JSONDecoder().decode(AudioOutputPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertNil(preferences.selectedUID)
        XCTAssertEqual(preferences.disabled.count, 2)
        let hardware = FakeAudioHardware()
        hardware.listFails = true
        XCTAssertFalse(try core(hardware).adjustVolume(preferences: preferences, increasing: true, repeatCount: 1))
        XCTAssertTrue(hardware.writes.isEmpty)
    }

    func testDiscoveredConnectionsDriveArcIconsAndRefreshWithoutChangingIdentity() throws {
        let hardware = FakeAudioHardware()
        let connections: [AudioOutputConnection] = [.usb, .bluetooth, .builtIn, .unknown]
        for (index, connection) in connections.enumerated() {
            let handle = UInt32(index + 1)
            hardware.add(handle, uid: "device-\(handle)", name: "Device \(handle)", channels: [2], main: 0.5)
            hardware.devices[handle]?.connection = connection
        }
        let mode = DialMode.volumeOutput
        let snapshot = try core(hardware).discover()
        XCTAssertEqual(snapshot.outputs.map(\.connection), connections)
        var navigation = try RadialMenuNavigation(
            items: AudioOutputMenu.items(modes: [mode], outputs: snapshot.outputs,
                                         preferences: AudioOutputPreferences()),
            selectedID: mode.id.uuidString, detentsPerItem: 1)
        _ = navigation.confirm()
        XCTAssertEqual(navigation.current.slots.compactMap(\.item).map(\.symbol),
                       ["hifispeaker", "cable.connector", "antenna.radiowaves.left.and.right",
                        "macbook.gen2", "speaker.wave.2.fill"])
        let id = "\(mode.id.uuidString).output.device-1"
        XCTAssertTrue(navigation.selectItem(id: id))
        hardware.devices[1]?.connection = .bluetooth
        try navigation.replaceItems(AudioOutputMenu.items(modes: [mode], outputs: core(hardware).discover().outputs,
                                                         preferences: AudioOutputPreferences()))
        XCTAssertEqual(navigation.current.selectedSlot.item?.id, id)
        XCTAssertEqual(navigation.current.selectedSlot.item?.symbol, "antenna.radiowaves.left.and.right")
    }

    func testConnectionReadFailureKeepsOutputUsableAndReportsFailure() throws {
        let hardware = FakeAudioHardware()
        hardware.add(1, uid: "usb", name: "USB", channels: [2], main: 0.5)
        hardware.devices[1]?.connection = .usb
        hardware.failingConnection.insert(1)
        let snapshot = try core(hardware).discover()
        XCTAssertEqual(snapshot.outputs, [AudioOutput(uid: "usb", name: "USB", supportsVolume: true)])
        XCTAssertEqual(snapshot.failures.count, 1)
        XCTAssertTrue(snapshot.discoveryError?.contains("connection") == true)
        XCTAssertEqual(try core(hardware).validateSelection("usb", preferences: AudioOutputPreferences(),
                                                          snapshot: snapshot), snapshot.outputs[0])
        XCTAssertTrue(hardware.writes.isEmpty)
    }

    // MARK: AudioOutputCore

    private func core(_ hardware: FakeAudioHardware) -> AudioOutputCore { AudioOutputCore(hardware: hardware) }

    private func selecting(_ uid: String?) -> AudioOutputPreferences {
        var preferences = AudioOutputPreferences()
        preferences.selectedUID = uid
        return preferences
    }

    func testDiscoveryFiltersSortsAndIsolatesBrokenDevices() throws {
        let hardware = FakeAudioHardware()
        hardware.add(1, uid: "z", name: "Zeta", channels: [2], main: 0.5)
        hardware.add(2, uid: "a", name: "alpha", channels: [1, 1], perChannel: [0.2, 0.4])
        hardware.add(3, uid: "dead", name: "Dead", channels: [2], main: 0.5, alive: false)
        hardware.add(4, uid: "mic", name: "Microphone", channels: [])
        hardware.add(5, uid: "hdmi", name: "Display", channels: [2])
        hardware.add(6, uid: "broken", name: "Broken", channels: [2], main: 0.5)
        hardware.failingUID.insert(6)
        hardware.add(7, uid: "z", name: "Duplicate", channels: [2], main: 0.5)
        hardware.add(8, uid: "noname", name: "", channels: [2], main: 0.5)
        hardware.add(9, uid: "partial", name: "Partial", channels: [2], perChannel: [0.5, nil])
        hardware.defaultHandle = 1

        let snapshot = try core(hardware).discover()
        XCTAssertEqual(snapshot.outputs.map(\.uid), ["a", "hdmi", "partial", "z"])
        XCTAssertEqual(snapshot.outputs.map(\.supportsVolume), [true, false, false, true])
        XCTAssertEqual(snapshot.defaultUID, "z")
        XCTAssertEqual(snapshot.handles, Array(1...9))
        XCTAssertEqual(snapshot.failures.count, 3)
        XCTAssertNotNil(snapshot.discoveryError)
    }

    func testDiscoveryReportsNoDefaultAndOverflowingChannels() throws {
        let hardware = FakeAudioHardware()
        hardware.add(1, uid: "huge", name: "Huge", channels: [UInt32.max, 1], main: 0.5)
        let snapshot = try core(hardware).discover()
        XCTAssertNil(snapshot.defaultUID)
        XCTAssertEqual(snapshot.outputs, [])
        XCTAssertEqual(snapshot.failures.count, 1)
        hardware.listFails = true
        XCTAssertThrowsError(try core(hardware).discover())
    }

    func testSelectionRevalidatesEligibilityAndDevice() throws {
        let hardware = FakeAudioHardware()
        hardware.add(1, uid: "spk", name: "Speakers", channels: [2], main: 0.5)
        hardware.add(2, uid: "hdmi", name: "Display", channels: [2])
        let core = core(hardware)
        var snapshot = try core.discover()
        var preferences = AudioOutputPreferences()
        XCTAssertEqual(try core.validateSelection("spk", preferences: preferences, snapshot: snapshot).name, "Speakers")
        XCTAssertThrowsError(try core.validateSelection("hdmi", preferences: preferences, snapshot: snapshot))
        XCTAssertThrowsError(try core.validateSelection("gone", preferences: preferences, snapshot: snapshot))
        preferences.disable(snapshot.outputs[1])
        XCTAssertThrowsError(try core.validateSelection("spk", preferences: preferences, snapshot: snapshot))
        preferences.enable("spk")

        hardware.devices[1]?.alive = false
        XCTAssertThrowsError(try core.validateSelection("spk", preferences: preferences, snapshot: snapshot)) {
            XCTAssertTrue($0.localizedDescription.contains("disconnected"))
        }
        hardware.devices[1]?.alive = true
        hardware.devices[1]?.main = nil
        XCTAssertThrowsError(try core.validateSelection("spk", preferences: preferences, snapshot: snapshot)) {
            XCTAssertTrue($0.localizedDescription.contains("no longer supports"))
        }

        snapshot.failures = ["discovery failed"]
        XCTAssertThrowsError(try core.validateSelection("other", preferences: preferences, snapshot: snapshot)) {
            XCTAssertEqual($0.localizedDescription, "discovery failed")
        }
    }

    func testAdjustUsesSystemPathWithoutSelectionOrWhileDisconnectedThenResumes() throws {
        let hardware = FakeAudioHardware()
        hardware.add(1, uid: "spk", name: "Speakers", channels: [2], main: 0.5)
        let core = core(hardware)
        XCTAssertFalse(try core.adjustVolume(preferences: selecting(nil), increasing: true, repeatCount: 1))
        XCTAssertFalse(try core.adjustVolume(preferences: selecting("absent"), increasing: true, repeatCount: 1))
        hardware.devices[1]?.alive = false
        XCTAssertFalse(try core.adjustVolume(preferences: selecting("spk"), increasing: true, repeatCount: 1))
        XCTAssertEqual(hardware.writes.count, 0)
        hardware.devices[1]?.alive = true
        XCTAssertTrue(try core.adjustVolume(preferences: selecting("spk"), increasing: true, repeatCount: 1))
        XCTAssertEqual(hardware.devices[1]?.main ?? 0, 0.5 + 1 / 64, accuracy: 0.0001)
        XCTAssertThrowsError(try core.adjustVolume(preferences: selecting(""), increasing: true, repeatCount: 1))
    }

    func testAdjustPreservesPerChannelBalance() throws {
        let hardware = FakeAudioHardware()
        hardware.add(1, uid: "usb", name: "USB", channels: [1, 1], perChannel: [0.25, 0.5])
        XCTAssertTrue(try core(hardware).adjustVolume(preferences: selecting("usb"), increasing: false, repeatCount: 64))
        XCTAssertEqual(hardware.devices[1]?.channels.compactMap { $0 }, [0, 0])
        hardware.devices[1]?.channels = [0.25, 0.5]
        XCTAssertTrue(try core(hardware).adjustVolume(preferences: selecting("usb"), increasing: false, repeatCount: 16))
        let levels = hardware.devices[1]?.channels.compactMap { $0 } ?? []
        XCTAssertEqual(levels[1], 0.25, accuracy: 0.0001)
        XCTAssertEqual(levels[0] / levels[1], 0.5, accuracy: 0.0001)
    }

    func testAdjustRejectsIdentityMismatchUnsupportedAndInvalidScalarsWithoutWriting() {
        let hardware = FakeAudioHardware()
        hardware.add(1, uid: "spk", name: "Speakers", channels: [2], main: .nan)
        hardware.add(2, uid: "hdmi", name: "Display", channels: [2])
        hardware.add(3, uid: "loud", name: "Loud", channels: [2], main: 1.5)
        let core = core(hardware)
        for uid in ["spk", "hdmi", "loud"] {
            XCTAssertThrowsError(try core.adjustVolume(preferences: selecting(uid), increasing: true, repeatCount: 1))
        }
        hardware.uidAliases["moved"] = 1
        XCTAssertThrowsError(try core.adjustVolume(preferences: selecting("moved"), increasing: true, repeatCount: 1))
        XCTAssertThrowsError(try core.adjustVolume(preferences: selecting("spk"), increasing: true, repeatCount: 0))
        XCTAssertEqual(hardware.writes.count, 0)
    }

    func testAdjustRollsBackPartialMultichannelWrites() {
        let hardware = FakeAudioHardware()
        hardware.add(1, uid: "usb", name: "USB", channels: [3], perChannel: [0.2, 0.4, 0.6])
        hardware.failingWriteElement = 3
        XCTAssertThrowsError(try core(hardware).adjustVolume(preferences: selecting("usb"), increasing: true,
                                                             repeatCount: 8))
        XCTAssertEqual(hardware.devices[1]?.channels.compactMap { $0 }, [0.2, 0.4, 0.6])
        XCTAssertEqual(hardware.writes.map(\.element), [1, 2, 3, 1, 2])

        hardware.failed = false
        hardware.failRestore = true
        XCTAssertThrowsError(try core(hardware).adjustVolume(preferences: selecting("usb"), increasing: true,
                                                             repeatCount: 8)) {
            XCTAssertTrue($0.localizedDescription.contains("Restore failed"))
        }
    }
}

private final class FakeAudioHardware: AudioHardware {
    struct Device {
        var uid: String
        var name: String
        var streams: [UInt32]
        var alive = true
        var main: Float?
        /// Index 0 is channel 1; nil means the channel is not writable.
        var channels: [Float?]
        var connection = AudioOutputConnection.unknown
    }
    struct FakeError: Error {}

    var devices: [AudioDeviceHandle: Device] = [:]
    var order: [AudioDeviceHandle] = []
    var defaultHandle: AudioDeviceHandle?
    var failingUID = Set<AudioDeviceHandle>()
    var failingConnection = Set<AudioDeviceHandle>()
    var uidAliases: [String: AudioDeviceHandle] = [:]
    var listFails = false
    var failingWriteElement: UInt32?
    var failRestore = false
    var failed = false
    var writes: [(element: UInt32, value: Float)] = []

    func add(_ handle: AudioDeviceHandle, uid: String, name: String, channels: [UInt32], main: Float? = nil,
             perChannel: [Float?] = [], alive: Bool = true) {
        devices[handle] = Device(uid: uid, name: name, streams: channels, alive: alive, main: main,
                                 channels: perChannel)
        order.append(handle)
    }

    private func device(_ handle: AudioDeviceHandle) throws -> Device {
        guard let device = devices[handle] else { throw FakeError() }
        return device
    }

    func deviceHandles() throws -> [AudioDeviceHandle] {
        if listFails { throw FakeError() }
        return order
    }
    func defaultOutputHandle() throws -> AudioDeviceHandle? { defaultHandle }
    func handle(forUID uid: String) throws -> AudioDeviceHandle? {
        uidAliases[uid] ?? order.first { devices[$0]?.uid == uid }
    }
    func isAlive(_ handle: AudioDeviceHandle) throws -> Bool { try device(handle).alive }
    func uid(of handle: AudioDeviceHandle) throws -> String {
        if failingUID.contains(handle) { throw FakeError() }
        return try device(handle).uid
    }
    func name(of handle: AudioDeviceHandle) throws -> String { try device(handle).name }
    func connection(of handle: AudioDeviceHandle) throws -> AudioOutputConnection {
        if failingConnection.contains(handle) { throw FakeError() }
        return try device(handle).connection
    }
    func outputStreamChannelCounts(_ handle: AudioDeviceHandle) throws -> [UInt32] { try device(handle).streams }
    func isVolumeWritable(_ handle: AudioDeviceHandle, element: UInt32) throws -> Bool {
        let device = try device(handle)
        if element == 0 { return device.main != nil }
        let index = Int(element) - 1
        return device.channels.indices.contains(index) && device.channels[index] != nil
    }
    func volume(_ handle: AudioDeviceHandle, element: UInt32) throws -> Float {
        let device = try device(handle)
        guard let value = element == 0 ? device.main : device.channels[Int(element) - 1] else { throw FakeError() }
        return value
    }
    func setVolume(_ handle: AudioDeviceHandle, element: UInt32, to value: Float) throws {
        writes.append((element, value))
        if element == failingWriteElement || (failRestore && failed) {
            failed = true
            throw FakeError()
        }
        if element == 0 { devices[handle]?.main = value } else { devices[handle]?.channels[Int(element) - 1] = value }
    }
}
