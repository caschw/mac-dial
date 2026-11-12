import Foundation

public enum AudioOutputConnection: Equatable {
    case usb
    case bluetooth
    case bluetoothSpeaker
    case bluetoothHeadphones
    case builtIn
    case unknown

    public var symbol: String {
        switch self {
        case .usb: return "cable.connector"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .bluetoothSpeaker: return "hifispeaker"
        case .bluetoothHeadphones: return "headphones"
        case .builtIn: return "macbook.gen2"
        case .unknown: return "speaker.wave.2.fill"
        }
    }

    /// Core Audio Bluetooth UIDs use a six-byte address followed by ":output".
    /// Class values are the Bluetooth assigned major/minor numbers, not a packed class.
    public static func bluetoothConnection(outputUID: String, pairedAddress: String,
                                           majorClass: UInt32, minorClass: UInt32) -> AudioOutputConnection? {
        guard outputUID.hasSuffix(":output") else { return nil }
        let address = String(outputUID.dropLast(":output".count))
        let pattern = "\\A(?:[0-9A-Fa-f]{2}(?:-[0-9A-Fa-f]{2}){5}|[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})\\z"
        guard address.range(of: pattern, options: .regularExpression) != nil,
              pairedAddress.range(of: pattern, options: .regularExpression) != nil,
              address.replacingOccurrences(of: ":", with: "-").lowercased()
                == pairedAddress.replacingOccurrences(of: ":", with: "-").lowercased() else { return nil }
        guard majorClass == 0x04 else { return .bluetooth }
        switch minorClass {
        case 0x01, 0x06: return .bluetoothHeadphones
        case 0x05: return .bluetoothSpeaker
        default: return .bluetooth
        }
    }
}

public struct AudioOutput: Equatable, Identifiable {
    public let uid: String
    public let name: String
    public let supportsVolume: Bool
    public let connection: AudioOutputConnection
    public var id: String { uid }

    public init(uid: String, name: String, supportsVolume: Bool, connection: AudioOutputConnection = .unknown) {
        self.uid = uid
        self.name = name
        self.supportsVolume = supportsVolume
        self.connection = connection
    }
}

public struct DisabledAudioOutput: Codable, Equatable, Identifiable {
    public let uid: String
    public let name: String
    public var id: String { uid }

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

public struct AudioOutputPreferences: Codable, Equatable {
    public var selectedUID: String?
    public private(set) var disabled: [DisabledAudioOutput] = []

    public init() {}

    private enum CodingKeys: String, CodingKey { case selectedUID, disabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedUID = try c.decodeIfPresent(String.self, forKey: .selectedUID)
        disabled = try c.decodeIfPresent([DisabledAudioOutput].self, forKey: .disabled) ?? []
        guard selectedUID != "", disabled.allSatisfy({ !$0.uid.isEmpty }),
              Set(disabled.map(\.uid)).count == disabled.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath,
                                                    debugDescription: "Audio output UIDs must be nonempty and disabled UIDs unique."))
        }
    }

    public func isDisabled(_ uid: String) -> Bool {
        disabled.contains(where: { $0.uid == uid })
    }

    public mutating func disable(_ output: AudioOutput) {
        guard !output.uid.isEmpty else {
            NSLog("MacDial: cannot disable an audio output with an empty UID")
            return
        }
        disabled.removeAll { $0.uid == output.uid }
        disabled.append(DisabledAudioOutput(uid: output.uid, name: output.name))
    }

    public mutating func enable(_ uid: String) {
        disabled.removeAll { $0.uid == uid }
    }

    public func eligibleOutputs(_ outputs: [AudioOutput]) -> [AudioOutput] {
        var seen = Set<String>()
        return outputs.filter {
            !$0.uid.isEmpty && $0.supportsVolume && !isDisabled($0.uid) && seen.insert($0.uid).inserted
        }
    }

    /// Hiding a device affects only menus, not the remembered volume target.
    public func effectiveUID(outputs: [AudioOutput], defaultUID: String?) -> String? {
        if let selectedUID, outputs.contains(where: { $0.uid == selectedUID }) {
            return selectedUID
        }
        return defaultUID
    }
}

public enum AudioVolumeError: Error, LocalizedError, Equatable {
    case invalidScalars
    case invalidRepeatCount

    public var errorDescription: String? {
        switch self {
        case .invalidScalars: return "The sound output reported invalid volume levels."
        case .invalidRepeatCount: return "The requested volume step count is invalid."
        }
    }
}

public enum AudioVolume {
    /// One Shift-Option volume-key step is 1/64 of the scalar range.
    /// Channel-only devices retain their balance relative to the loudest channel.
    public static func adjusted(_ levels: [Float], increasing: Bool, repeatCount: Int) throws -> [Float] {
        guard !levels.isEmpty, levels.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw AudioVolumeError.invalidScalars
        }
        guard repeatCount > 0 else { throw AudioVolumeError.invalidRepeatCount }
        let peak = levels.max()!
        let step = Float(min(repeatCount, 64)) / 64
        let next = min(1, max(0, peak + (increasing ? step : -step)))
        if peak == 0 { return levels.map { _ in next } }
        return levels.map { min(1, max(0, ($0 / peak) * next)) }
    }
}

public enum DialMenuChoice {
    case mode(DialMode)
    case systemDefaultAudioOutput
    case audioOutput(String)
    case information(String)
}

public enum AudioOutputMenu {
    public static func items(modes: [DialMode], outputs: [AudioOutput],
                             preferences: AudioOutputPreferences, error: String? = nil) -> [RadialMenuItem<DialMenuChoice>] {
        modes.map { mode in
            guard mode.kind == .volumeOutput else {
                return .leaf(id: mode.id.uuidString, title: mode.name, symbol: mode.icon, payload: .mode(mode))
            }
            var children: [RadialMenuItem<DialMenuChoice>] = [
                .leaf(id: "\(mode.id.uuidString).system-default", title: "System default",
                      symbol: "speaker", payload: .systemDefaultAudioOutput)
            ]
            children += preferences.eligibleOutputs(outputs).map {
                .leaf(id: "\(mode.id.uuidString).output.\($0.uid)", title: $0.name,
                      symbol: $0.connection.symbol, payload: .audioOutput($0.uid))
            }
            if let error {
                children.append(.leaf(id: "\(mode.id.uuidString).error", title: error,
                                      symbol: "exclamationmark.triangle", payload: .information(error)))
            }
            return .group(id: mode.id.uuidString, title: mode.name, symbol: mode.icon, children: children)
        }
    }

    /// Enabled modes, plus a requested Volume Output mode even when it is hidden from cycling.
    public static func modes(for config: DialConfig, requestedOutputModeID: UUID?) -> [DialMode] {
        var modes = config.enabledModes
        if let id = requestedOutputModeID, !modes.contains(where: { $0.id == id }),
           let mode = config.modes.first(where: { $0.id == id && $0.kind == .volumeOutput }) {
            modes.append(mode)
        }
        return modes
    }

    /// The arc item for the remembered target; System default when no device is chosen.
    /// Nil when the chosen device is hidden or absent, so the arc keeps its default selection.
    public static func preferredItemID(in items: [RadialMenuItem<DialMenuChoice>], selectedUID: String?) -> String? {
        items.first(where: {
            if case .leaf(.audioOutput(let uid)) = $0.content { return uid == selectedUID }
            if case .leaf(.systemDefaultAudioOutput) = $0.content { return selectedUID == nil }
            return false
        })?.id
    }

    /// HUD capsule for a confirmed choice; nil output means System default.
    public static func confirmation(for output: AudioOutput?) -> (symbol: String, title: String) {
        guard let output else { return ("speaker", "Sound output changed to System default") }
        return (output.connection.symbol, "Sound output changed to \(output.name)")
    }
}

/// An opaque native audio object handle; zero is the unknown object.
public typealias AudioDeviceHandle = UInt32

/// Minimal native audio surface used by `AudioOutputCore`. Implementations validate
/// native property sizes; the core validates identities, channel counts, and scalars.
public protocol AudioHardware {
    func deviceHandles() throws -> [AudioDeviceHandle]
    /// Returns nil when the system reports no default output.
    func defaultOutputHandle() throws -> AudioDeviceHandle?
    /// Returns nil when no device currently has the UID.
    func handle(forUID uid: String) throws -> AudioDeviceHandle?
    func isAlive(_ device: AudioDeviceHandle) throws -> Bool
    func uid(of device: AudioDeviceHandle) throws -> String
    func name(of device: AudioDeviceHandle) throws -> String
    /// Unknown is valid when the transport property is absent or unrecognized.
    func connection(of device: AudioDeviceHandle) throws -> AudioOutputConnection
    /// Per-stream output channel counts.
    func outputStreamChannelCounts(_ device: AudioDeviceHandle) throws -> [UInt32]
    func isVolumeWritable(_ device: AudioDeviceHandle, element: UInt32) throws -> Bool
    func volume(_ device: AudioDeviceHandle, element: UInt32) throws -> Float
    func setVolume(_ device: AudioDeviceHandle, element: UInt32, to value: Float) throws
}

public struct AudioOutputError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct AudioOutputSnapshot: Equatable {
    public var outputs: [AudioOutput]
    public var defaultUID: String?
    /// Handles of every reported device, for change observation.
    public var handles: [AudioDeviceHandle]
    /// Devices that could not be inspected; other devices remain usable.
    public var failures: [String]

    public init(outputs: [AudioOutput], defaultUID: String?, handles: [AudioDeviceHandle], failures: [String]) {
        self.outputs = outputs
        self.defaultUID = defaultUID
        self.handles = handles
        self.failures = failures
    }

    public var discoveryError: String? { failures.isEmpty ? nil : failures.joined(separator: "\n") }
}

/// Platform-independent discovery, selection, and selected-device volume logic.
public struct AudioOutputCore {
    public static let mainElement: UInt32 = 0
    public let hardware: AudioHardware

    public init(hardware: AudioHardware) { self.hardware = hardware }

    public func discover() throws -> AudioOutputSnapshot {
        let handles = try hardware.deviceHandles()
        var outputs: [AudioOutput] = []
        var seen = Set<String>()
        var failures: [String] = []
        for device in handles {
            do {
                guard try hardware.isAlive(device), try channelCount(device) > 0 else { continue }
                let uid = try nonempty(hardware.uid(of: device))
                guard seen.insert(uid).inserted else {
                    throw AudioOutputError("Core Audio reported duplicate output identities.")
                }
                let name = try nonempty(hardware.name(of: device))
                let supportsVolume = !(try volumeElements(device)).isEmpty
                var connection = AudioOutputConnection.unknown
                do {
                    connection = try hardware.connection(of: device)
                } catch {
                    failures.append("Cannot inspect audio device \(device) connection: \(error.localizedDescription)")
                }
                outputs.append(AudioOutput(uid: uid, name: name, supportsVolume: supportsVolume,
                                           connection: connection))
            } catch {
                failures.append("Cannot inspect audio device \(device): \(error.localizedDescription)")
            }
        }
        var defaultUID: String?
        if let device = try hardware.defaultOutputHandle(), device != 0 {
            defaultUID = try nonempty(hardware.uid(of: device))
        }
        outputs.sort {
            $0.name == $1.name ? $0.uid < $1.uid : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return AudioOutputSnapshot(outputs: outputs, defaultUID: defaultUID, handles: handles, failures: failures)
    }

    /// Revalidates a menu choice against fresh discovery and the device itself.
    public func validateSelection(_ uid: String, preferences: AudioOutputPreferences,
                                  snapshot: AudioOutputSnapshot) throws -> AudioOutput {
        if let error = snapshot.discoveryError, !snapshot.outputs.contains(where: { $0.uid == uid }) {
            throw AudioOutputError(error)
        }
        guard let output = preferences.eligibleOutputs(snapshot.outputs).first(where: { $0.uid == uid }) else {
            throw AudioOutputError("That volume output is no longer available. Choose another output.")
        }
        guard let device = try resolve(uid) else {
            throw AudioOutputError("That sound output disconnected. Choose another output.")
        }
        guard !(try volumeElements(device)).isEmpty else {
            throw AudioOutputError("\(output.name) no longer supports software volume control.")
        }
        return output
    }

    /// Returns false when the system volume-key path should be used: no chosen
    /// target, or the chosen target is disconnected. Throws after a failed attempt
    /// on an available chosen target; it never falls back to another device then.
    public func adjustVolume(preferences: AudioOutputPreferences, increasing: Bool, repeatCount: Int) throws -> Bool {
        guard let uid = preferences.selectedUID else { return false }
        guard let device = try resolve(uid) else { return false }
        let elements = try volumeElements(device)
        guard !elements.isEmpty else {
            throw AudioOutputError("The chosen volume output cannot be adjusted in software.")
        }
        let old = try elements.map { try hardware.volume(device, element: $0) }
        let next = try AudioVolume.adjusted(old, increasing: increasing, repeatCount: repeatCount)
        var written = 0
        do {
            for (element, value) in zip(elements, next) {
                try hardware.setVolume(device, element: element, to: value)
                written += 1
            }
        } catch {
            // Avoid leaving a partially updated multichannel balance.
            var messages = [error.localizedDescription]
            for index in 0..<written {
                do { try hardware.setVolume(device, element: elements[index], to: old[index]) }
                catch { messages.append("Restore failed: \(error.localizedDescription)") }
            }
            throw AudioOutputError(messages.joined(separator: "\n"))
        }
        return true
    }

    /// Resolves the chosen identity directly, so an unrelated broken device cannot block volume.
    public func resolve(_ uid: String) throws -> AudioDeviceHandle? {
        guard !uid.isEmpty else { throw AudioOutputError("The selected sound output has an invalid identity.") }
        guard let device = try hardware.handle(forUID: uid), device != 0, try hardware.isAlive(device) else {
            return nil
        }
        guard try hardware.uid(of: device) == uid, try channelCount(device) > 0 else {
            throw AudioOutputError("The selected sound output identity changed during discovery.")
        }
        return device
    }

    /// The main control if writable; otherwise every channel, so balance is never shifted.
    public func volumeElements(_ device: AudioDeviceHandle) throws -> [UInt32] {
        if try hardware.isVolumeWritable(device, element: Self.mainElement) { return [Self.mainElement] }
        let count = try channelCount(device)
        guard count > 0 else { return [] }
        var elements: [UInt32] = []
        for channel in 1...count {
            guard try hardware.isVolumeWritable(device, element: channel) else { return [] }
            elements.append(channel)
        }
        return elements
    }

    public func channelCount(_ device: AudioDeviceHandle) throws -> UInt32 {
        var count: UInt32 = 0
        for channels in try hardware.outputStreamChannelCounts(device) {
            let (sum, overflow) = count.addingReportingOverflow(channels)
            guard !overflow else { throw AudioOutputError("The sound output reported an overflowing channel count.") }
            count = sum
        }
        return count
    }

    private func nonempty(_ value: String) throws -> String {
        guard !value.isEmpty else { throw AudioOutputError("Core Audio reported an empty sound output identity or name.") }
        return value
    }
}
