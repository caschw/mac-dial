import Foundation

/// Loads and saves settings without overwriting documents this version cannot fully understand.
public final class DialConfigStorage {
    public struct Recovery: Equatable {
        public let reason: String
        public let originalData: Data?
        public let suggestedFileName: String
    }

    public enum SaveError: LocalizedError, Equatable {
        case protectedSettings
        case changedSettings

        public var errorDescription: String? {
            switch self {
            case .protectedSettings:
                return "The original saved settings must be explicitly replaced before changes can be saved."
            case .changedSettings:
                return "The saved settings changed outside this Mac Dial instance. Review the latest original before replacing it."
            }
        }
    }

    private enum Snapshot: Equatable {
        case missing
        case data(Data)
        case propertyList(Data)
    }

    public static let key = "dialConfig.v2"

    public let loadedConfig: DialConfig
    public private(set) var recovery: Recovery?
    private let defaults: UserDefaults
    private var observedSnapshot: Snapshot?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.key)
        observedSnapshot = Self.snapshot(stored)
        guard let stored else {
            loadedConfig = DialConfig()
            recovery = nil
            return
        }
        guard let data = stored as? Data else {
            loadedConfig = DialConfig()
            recovery = Self.recovery(for: stored, reason: "The saved settings use an unsupported storage format.")
            return
        }

        let decoder = JSONDecoder()
        do {
            loadedConfig = try decoder.decode(DialConfig.self, from: data)
        } catch {
            loadedConfig = DialConfig()
            recovery = Recovery(reason: "The saved settings could not be read: \(Self.describe(error, data: data))",
                                originalData: data, suggestedFileName: "MacDial-original-settings.json")
            return
        }

        do {
            _ = try decoder.decode(KnownFields.self, from: data)
            let original = try JSONSerialization.jsonObject(with: data)
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(loadedConfig))
            if let path = Self.unknownKey(in: original, matching: encoded, path: "") {
                recovery = Recovery(reason: "The saved settings contain an unrecognized field: \(path).",
                                    originalData: data, suggestedFileName: "MacDial-original-settings.json")
            } else {
                recovery = nil
            }
        } catch {
            recovery = Recovery(reason: "The saved settings contain an incompatible value: \(Self.describe(error, data: data))",
                                originalData: data, suggestedFileName: "MacDial-original-settings.json")
        }
    }

    public func save(_ config: DialConfig) throws {
        guard recovery == nil else { throw SaveError.protectedSettings }
        let data = try JSONEncoder().encode(config)
        try ensureUnchanged()
        defaults.set(data, forKey: Self.key)
        observedSnapshot = .data(data)
    }

    /// Call only after the user has confirmed replacing the original document.
    public func replaceSavedSettings(with config: DialConfig) throws {
        let data = try JSONEncoder().encode(config)
        try ensureUnchanged()
        defaults.set(data, forKey: Self.key)
        observedSnapshot = .data(data)
        recovery = nil
    }

    private func ensureUnchanged() throws {
        let stored = defaults.object(forKey: Self.key)
        let current = Self.snapshot(stored)
        guard let observedSnapshot, let current, observedSnapshot == current else {
            observedSnapshot = current
            recovery = Self.recovery(for: stored, reason: "The saved settings changed outside this Mac Dial instance.")
            throw SaveError.changedSettings
        }
    }

    private static func snapshot(_ stored: Any?) -> Snapshot? {
        guard let stored else { return .missing }
        if let data = stored as? Data { return .data(data) }
        do {
            return .propertyList(try PropertyListSerialization.data(fromPropertyList: stored, format: .binary, options: 0))
        } catch {
            NSLog("MacDial: unable to compare the saved-settings format: %@", String(describing: error))
            return nil
        }
    }

    private static func recovery(for stored: Any?, reason: String) -> Recovery {
        if let data = stored as? Data {
            return Recovery(reason: reason, originalData: data, suggestedFileName: "MacDial-original-settings.json")
        }
        let backup: Data?
        if let stored {
            do {
                backup = try PropertyListSerialization.data(fromPropertyList: stored, format: .xml, options: 0)
            } catch {
                NSLog("MacDial: unable to export the unsupported saved-settings format: %@", String(describing: error))
                backup = nil
            }
        } else {
            backup = nil
        }
        return Recovery(reason: reason, originalData: backup, suggestedFileName: "MacDial-original-settings.plist")
    }

    private static func describe(_ error: Error, data: Data) -> String {
        let context: DecodingError.Context
        let missingKey: CodingKey?
        switch error {
        case DecodingError.keyNotFound(let key, let value):
            context = value
            missingKey = key
        case DecodingError.typeMismatch(_, let value),
             DecodingError.valueNotFound(_, let value),
             DecodingError.dataCorrupted(let value):
            context = value
            missingKey = nil
        default:
            return error.localizedDescription
        }
        let path = (context.codingPath + [missingKey].compactMap { $0 }).reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                if !result.isEmpty { result += "." }
                result += key.stringValue
            }
        }
        if path.isEmpty,
           (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil,
           let underlying = context.underlyingError as NSError?,
           let detail = underlying.userInfo[NSDebugDescriptionErrorKey] as? String {
            return detail
        }
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    }

    private static func unknownKey(in original: Any, matching encoded: Any, path: String) -> String? {
        if let source = original as? [String: Any], let target = encoded as? [String: Any] {
            for key in source.keys.sorted() {
                let value = source[key]!
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                guard let encodedValue = target[key] else {
                    if value is NSNull && isKnownOptional(key, in: path) { continue }
                    return childPath
                }
                if let unknown = unknownKey(in: value, matching: encodedValue, path: childPath) {
                    return unknown
                }
            }
        } else if let source = original as? [Any], let target = encoded as? [Any] {
            for (index, pair) in zip(source, target).enumerated() {
                if let unknown = unknownKey(in: pair.0, matching: pair.1, path: "\(path)[\(index)]") {
                    return unknown
                }
            }
        }
        return nil
    }

    private static func isKnownOptional(_ key: String, in path: String) -> Bool {
        if path.isEmpty { return key == "currentModeID" }
        if path == "audioOutput" { return key == "selectedUID" }
        if path.hasPrefix("modes[") && !path.contains(".") { return key == "kind" }
        if path.hasSuffix(".rotate") || path.hasSuffix(".pressedRotate") {
            return key == "clockwise" || key == "counterClockwise"
        }
        if path.hasSuffix(".click") || path.hasSuffix(".doubleClick") || path.hasSuffix(".longPress") {
            return key == "shortcut" || key == "appPath"
        }
        return false
    }
}

/// Unlike DialConfig's compatibility decoder, this probe reports invalid present fields.
private struct KnownFields: Decodable {
    private enum CodingKeys: String, CodingKey {
        case modes, currentModeID, stepsPerRevolution, detentHaptics, menuHaptics, showHUD
        case radialAtCursor, menuBarGlyph, doubleClickInterval, longPressDuration, fastWake
        case audioOutput, volumeOutputModeIntroduced
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func check<T: Decodable>(_ type: T.Type, _ key: CodingKeys) throws {
            if container.contains(key) { _ = try container.decode(type, forKey: key) }
        }
        try check([DialMode].self, .modes)
        try check(AudioOutputPreferences.self, .audioOutput)
        try check(Bool.self, .volumeOutputModeIntroduced)
        if container.contains(.currentModeID) { _ = try container.decodeIfPresent(UUID.self, forKey: .currentModeID) }
        try check(Int.self, .stepsPerRevolution)
        try check(Bool.self, .detentHaptics)
        try check(Bool.self, .menuHaptics)
        try check(Bool.self, .showHUD)
        try check(Bool.self, .radialAtCursor)
        try check(MenuBarGlyph.self, .menuBarGlyph)
        try check(Double.self, .doubleClickInterval)
        try check(Double.self, .longPressDuration)
        try check(Bool.self, .fastWake)
    }
}
