import Foundation
import Combine
import CoreAudio
import CoreBluetooth
import IOBluetooth
import MacDialKit

/// Core Audio ownership stays in the app; callbacks and clients use the main queue.
final class AudioOutputService: ObservableObject, AudioHardware {
    @Published private(set) var outputs: [AudioOutput] = []
    @Published private(set) var defaultUID: String?
    @Published private(set) var error: String?
    var onError: ((String) -> Void)?

    private struct Listener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var listeners: [Listener] = []
    private var refreshPending = false
    private var started = false

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()
    }

    func stop() {
        started = false
        removeListeners()
    }

    deinit { removeListeners() }

    private var core: AudioOutputCore { AudioOutputCore(hardware: self) }

    func refresh() {
        do {
            let snapshot = try core.discover()
            for failure in snapshot.failures { NSLog("MacDial: %@", failure) }
            if outputs != snapshot.outputs { outputs = snapshot.outputs }
            if defaultUID != snapshot.defaultUID { defaultUID = snapshot.defaultUID }
            if error != snapshot.discoveryError { error = snapshot.discoveryError }
            installListeners(snapshot.handles)
        } catch {
            report(error)
            self.error = error.localizedDescription
            // Keep watching the system even if discovery failed on launch.
            installListeners([])
        }
    }

    func select(_ uid: String, preferences: AudioOutputPreferences) throws -> AudioOutput {
        refresh()
        let snapshot = AudioOutputSnapshot(outputs: outputs, defaultUID: defaultUID, handles: [],
                                           failures: error.map { [$0] } ?? [])
        return try core.validateSelection(uid, preferences: preferences, snapshot: snapshot)
    }

    /// Returns false only when the existing system volume-key path should be used.
    func adjustVolume(preferences: AudioOutputPreferences, increasing: Bool, repeatCount: Int) -> Bool {
        do {
            return try core.adjustVolume(preferences: preferences, increasing: increasing, repeatCount: repeatCount)
        } catch {
            report(error)
            return true
        }
    }

    // MARK: AudioHardware

    func deviceHandles() throws -> [AudioDeviceHandle] {
        try array(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices)
    }

    func defaultOutputHandle() throws -> AudioDeviceHandle? {
        let id = try scalar(AudioObjectID(kAudioObjectSystemObject),
                            selector: kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0))
        return id == kAudioObjectUnknown ? nil : id
    }

    func handle(forUID uid: String) throws -> AudioDeviceHandle? {
        var uid = uid as CFString
        var address = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try withUnsafePointer(to: &uid) { qualifier in
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                  UInt32(MemoryLayout<CFString>.size), qualifier, &size, &id),
                      "resolve the chosen sound output")
        }
        guard size == MemoryLayout<AudioObjectID>.size else {
            throw Failure(message: "Core Audio reported an invalid device identity size.")
        }
        return id == kAudioObjectUnknown ? nil : id
    }

    func isAlive(_ device: AudioDeviceHandle) throws -> Bool {
        try scalar(device, selector: kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0)) != 0
    }

    func uid(of device: AudioDeviceHandle) throws -> String {
        try string(device, selector: kAudioDevicePropertyDeviceUID)
    }

    func name(of device: AudioDeviceHandle) throws -> String {
        try string(device, selector: kAudioObjectPropertyName)
    }

    func connection(of device: AudioDeviceHandle) throws -> AudioOutputConnection {
        var property = address(kAudioDevicePropertyTransportType)
        guard AudioObjectHasProperty(device, &property) else { return .unknown }
        let transport = try scalar(device, selector: kAudioDevicePropertyTransportType, initial: UInt32(0))
        switch transport {
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            // Reading paired devices requires the app's existing Bluetooth grant.
            guard CBManager.authorization == .allowedAlways else { return .bluetooth }
            let outputUID = try uid(of: device)
            for case let paired as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] {
                guard let pairedAddress = paired.addressString else { continue }
                if let connection = AudioOutputConnection.bluetoothConnection(
                    outputUID: outputUID, pairedAddress: pairedAddress,
                    majorClass: UInt32(paired.deviceClassMajor), minorClass: UInt32(paired.deviceClassMinor)) {
                    return connection
                }
            }
            return .bluetooth
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        default: return .unknown
        }
    }

    func outputStreamChannelCounts(_ device: AudioDeviceHandle) throws -> [UInt32] {
        let streams: [AudioStreamID] = try array(device, selector: kAudioDevicePropertyStreams,
                                                scope: kAudioDevicePropertyScopeOutput)
        return try streams.map {
            try scalar($0, selector: kAudioStreamPropertyVirtualFormat,
                       initial: AudioStreamBasicDescription()).mChannelsPerFrame
        }
    }

    func isVolumeWritable(_ device: AudioDeviceHandle, element: UInt32) throws -> Bool {
        var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
                              element: element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        try check(AudioObjectIsPropertySettable(device, &address, &settable), "inspect volume control")
        return settable.boolValue
    }

    func volume(_ device: AudioDeviceHandle, element: UInt32) throws -> Float {
        try scalar(device, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
                   element: element, initial: Float(0))
    }

    func setVolume(_ device: AudioDeviceHandle, element: UInt32, to value: Float) throws {
        try writeVolume(device, element: element, value: value)
    }

    private func writeVolume(_ id: AudioObjectID, element: AudioObjectPropertyElement, value: Float) throws {
        guard value.isFinite, (0...1).contains(value) else { throw AudioVolumeError.invalidScalars }
        var value = value
        var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
        try check(AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &value),
                  "change sound output volume")
    }

    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func scalar<T>(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                           scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                           element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, initial: T) throws -> T {
        var address = address(selector, scope: scope, element: element)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size), "read sound output property size")
        guard size == MemoryLayout<T>.size else { throw Failure(message: "Core Audio reported an invalid property size.") }
        var value = initial
        try withUnsafeMutablePointer(to: &value) {
            try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0), "read sound output property")
        }
        guard size == MemoryLayout<T>.size else { throw Failure(message: "Core Audio changed a property size during discovery.") }
        return value
    }

    private func string(_ id: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        let value: CFString? = try scalar(id, selector: selector, initial: Optional<CFString>.none)
        guard let value, !(value as String).isEmpty else {
            throw Failure(message: "Core Audio reported an empty sound output identity or name.")
        }
        return value as String
    }

    private func array<T: FixedWidthInteger>(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [T] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size), "read audio device list size")
        let stride = MemoryLayout<T>.stride
        guard Int(size) % stride == 0 else { throw Failure(message: "Core Audio reported an invalid device list size.") }
        var values = Array(repeating: T.zero, count: Int(size) / stride)
        let capacity = size
        if size == 0 { return [] }
        try values.withUnsafeMutableBytes {
            try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0.baseAddress!), "read audio device list")
        }
        guard size <= capacity, Int(size) % stride == 0 else {
            throw Failure(message: "Core Audio changed the device list size during discovery.")
        }
        return Array(values.prefix(Int(size) / stride))
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw Failure(message: "Unable to \(operation) (Core Audio error \(status)).") }
    }

    private func report(_ error: Error) {
        NSLog("MacDial: audio output: %@", error.localizedDescription)
        onError?(error.localizedDescription)
    }

    private func installListeners(_ ids: [AudioObjectID]) {
        guard started else { return }
        removeListeners()
        addListener(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices)
        addListener(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice)
        for id in ids {
            for selector in [kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyOwnedObjects,
                             kAudioObjectPropertyName, kAudioDevicePropertyTransportType] {
                addListener(id, selector: selector)
            }
            addListener(id, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            do {
                let streams: [AudioStreamID] = try array(id, selector: kAudioDevicePropertyStreams,
                                                        scope: kAudioDevicePropertyScopeOutput)
                for stream in streams {
                    addListener(stream, selector: kAudioStreamPropertyVirtualFormat)
                }
            } catch {
                self.error = error.localizedDescription
                report(error)
            }
        }
    }

    private func addListener(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        var address = address(selector, scope: scope, element: kAudioObjectPropertyElementWildcard)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.started, !self.refreshPending else { return }
            self.refreshPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshPending = false
                if self.started { self.refresh() }
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(id, &address, .main, block)
        if status == noErr {
            listeners.append(Listener(object: id, address: address, block: block))
        } else {
            let failure = Failure(message: "Unable to watch sound output changes (Core Audio error \(status)).")
            error = failure.message
            report(failure)
        }
    }

    private func removeListeners() {
        for var listener in listeners {
            let status = AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, .main, listener.block)
            if status != noErr { NSLog("MacDial: unable to remove audio listener: %d", status) }
        }
        listeners.removeAll()
    }
}
