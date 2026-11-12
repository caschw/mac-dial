import Foundation

public struct AudioOutput: Equatable, Identifiable {
    public let uid: String
    public let name: String
    public let supportsVolume: Bool
    public var id: String { uid }

    public init(uid: String, name: String, supportsVolume: Bool) {
        self.uid = uid
        self.name = name
        self.supportsVolume = supportsVolume
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
            var children: [RadialMenuItem<DialMenuChoice>] = preferences.eligibleOutputs(outputs).map {
                .leaf(id: "\(mode.id.uuidString).output.\($0.uid)", title: $0.name,
                      symbol: "speaker.wave.2.fill", payload: .audioOutput($0.uid))
            }
            if children.isEmpty {
                let message = error ?? "No available volume outputs"
                children = [.leaf(id: "\(mode.id.uuidString).empty", title: message,
                                  symbol: "speaker.slash", payload: .information(message))]
            }
            return .group(id: mode.id.uuidString, title: mode.name, symbol: mode.icon, children: children)
        }
    }
}
