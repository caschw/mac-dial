import Foundation
import Combine
import CoreAudio
import MacDialKit

/// Core Audio ownership stays in the app; callbacks and clients use the main queue.
final class AudioOutputService: ObservableObject {
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

    func refresh() {
        do {
            let ids: [AudioObjectID] = try array(AudioObjectID(kAudioObjectSystemObject),
                                               selector: kAudioHardwarePropertyDevices)
            var discovered: [AudioOutput] = []
            var seen = Set<String>()
            var failures: [String] = []
            for id in ids {
                do {
                    guard try scalar(id, selector: kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0)) != 0,
                          try channelCount(id) > 0 else { continue }
                    let uid = try string(id, selector: kAudioDevicePropertyDeviceUID)
                    guard seen.insert(uid).inserted else {
                        throw Failure(message: "Core Audio reported duplicate output identities.")
                    }
                    discovered.append(AudioOutput(uid: uid, name: try string(id, selector: kAudioObjectPropertyName),
                                                  supportsVolume: !(try volumeElements(id)).isEmpty))
                } catch {
                    let message = "Cannot inspect audio device \(id): \(error.localizedDescription)"
                    NSLog("MacDial: %@", message)
                    failures.append(message)
                }
            }
            let defaultID = try scalar(AudioObjectID(kAudioObjectSystemObject),
                                       selector: kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0))
            let currentUID = defaultID == kAudioObjectUnknown ? nil
                : try string(defaultID, selector: kAudioDevicePropertyDeviceUID)
            let sorted = discovered.sorted {
                $0.name == $1.name ? $0.uid < $1.uid : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            if outputs != sorted { outputs = sorted }
            if defaultUID != currentUID { defaultUID = currentUID }
            let discoveryError = failures.isEmpty ? nil : failures.joined(separator: "\n")
            if self.error != discoveryError { self.error = discoveryError }
            installListeners(ids)
        } catch {
            report(error)
            self.error = error.localizedDescription
            // Keep watching the system even if discovery failed on launch.
            installListeners([])
        }
    }

    func select(_ uid: String, preferences: AudioOutputPreferences) throws -> AudioOutput {
        refresh()
        guard error == nil || outputs.contains(where: { $0.uid == uid }) else {
            throw Failure(message: error ?? "Sound output discovery failed.")
        }
        guard let output = preferences.eligibleOutputs(outputs).first(where: { $0.uid == uid }) else {
            throw Failure(message: "That volume output is no longer available. Choose another output.")
        }
        let id = try deviceID(uid)
        guard !(try volumeElements(id)).isEmpty else {
            throw Failure(message: "\(output.name) no longer supports software volume control.")
        }
        return output
    }

    /// Returns false only when the existing system volume-key path should be used.
    func adjustVolume(preferences: AudioOutputPreferences, increasing: Bool, repeatCount: Int) -> Bool {
        guard let uid = preferences.selectedUID else { return false }
        do {
            guard let id = try findDeviceID(uid) else {
                // A remembered, disconnected target uses the current system output temporarily.
                return false
            }
            let elements = try volumeElements(id)
            guard !elements.isEmpty else {
                throw Failure(message: "The chosen volume output cannot be adjusted in software.")
            }
            let old = try elements.map {
                try scalar(id, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
                           element: $0, initial: Float(0))
            }
            let next = try AudioVolume.adjusted(old, increasing: increasing, repeatCount: repeatCount)
            var written = 0
            do {
                for (element, value) in zip(elements, next) {
                    try writeVolume(id, element: element, value: value)
                    written += 1
                }
            } catch {
                // Avoid leaving a partially updated multichannel balance.
                for index in 0..<written {
                    do { try writeVolume(id, element: elements[index], value: old[index]) }
                    catch { report(error) }
                }
                throw error
            }
        } catch {
            report(error)
        }
        return true
    }

    private func findDeviceID(_ uid: String) throws -> AudioObjectID? {
        guard !uid.isEmpty else { throw Failure(message: "The selected sound output has an invalid identity.") }
        // Resolve the selected identity directly: a broken unrelated device must not block volume.
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
        guard id != kAudioObjectUnknown,
              try scalar(id, selector: kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0)) != 0 else { return nil }
        guard try string(id, selector: kAudioDevicePropertyDeviceUID) == uid as String,
              try channelCount(id) > 0 else {
            throw Failure(message: "The selected sound output identity changed during discovery.")
        }
        return id
    }

    private func deviceID(_ uid: String) throws -> AudioObjectID {
        guard let id = try findDeviceID(uid) else {
            throw Failure(message: "That sound output disconnected. Choose another output.")
        }
        return id
    }

    private func channelCount(_ id: AudioObjectID) throws -> UInt32 {
        let streams: [AudioStreamID] = try array(id, selector: kAudioDevicePropertyStreams,
                                                scope: kAudioDevicePropertyScopeOutput)
        var count: UInt32 = 0
        for stream in streams {
            let format = try scalar(stream, selector: kAudioStreamPropertyVirtualFormat,
                                    initial: AudioStreamBasicDescription())
            let (sum, overflow) = count.addingReportingOverflow(format.mChannelsPerFrame)
            guard !overflow else { throw Failure(message: "The sound output reported an overflowing channel count.") }
            count = sum
        }
        return count
    }

    private func volumeElements(_ id: AudioObjectID) throws -> [AudioObjectPropertyElement] {
        func writable(_ element: AudioObjectPropertyElement) throws -> Bool {
            var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
                                  element: element)
            guard AudioObjectHasProperty(id, &address) else { return false }
            var settable = DarwinBoolean(false)
            try check(AudioObjectIsPropertySettable(id, &address, &settable), "inspect volume control")
            return settable.boolValue
        }
        if try writable(kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        let count = try channelCount(id)
        guard count > 0 else { return [] }
        var elements: [AudioObjectPropertyElement] = []
        for channel in 1...count {
            // All channels must be writable to control the output without shifting balance.
            guard try writable(channel) else { return [] }
            elements.append(channel)
        }
        return elements
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
                             kAudioObjectPropertyName] {
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
