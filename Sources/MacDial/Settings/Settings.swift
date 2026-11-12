import Foundation
import AppKit
import Combine
import MacDialKit

extension KeyShortcut {
    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var displayString: String {
        var s = ""
        let flags = modifierFlags
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + keyName
    }

    static func make(_ keyCode: UInt16, _ name: String, _ flags: NSEvent.ModifierFlags) -> KeyShortcut {
        KeyShortcut(keyCode: keyCode, modifiers: flags.rawValue, keyName: name)
    }
}

final class SettingsStore: ObservableObject {
    private let storage: DialConfigStorage
    @Published private(set) var recovery: DialConfigStorage.Recovery?
    var onVolumeOutput: ((UUID) -> Void)?
    private var cyclingUtility: (id: UUID, operatingID: UUID)?

    @Published var config: DialConfig {
        didSet {
            if config.currentModeID != oldValue.currentModeID { cyclingUtility = nil }
            guard config != oldValue else { return }
            guard recovery == nil else { return }
            do {
                try storage.save(config)
            } catch {
                recovery = storage.recovery
                NSLog("MacDial: unable to save configuration: %@", String(describing: error))
            }
        }
    }

    init() {
        storage = DialConfigStorage()
        config = storage.loadedConfig
        recovery = storage.recovery
        if let recovery {
            NSLog("MacDial: saved settings protected: %@", recovery.reason)
        }
        if config.modes.isEmpty { config.modes = DialMode.defaults }
        if !config.volumeOutputModeIntroduced {
            config.introduceVolumeOutputMode()
            if recovery == nil {
                do { try storage.save(config) }
                catch {
                    recovery = storage.recovery
                    NSLog("MacDial: unable to save volume output migration: %@", error.localizedDescription)
                }
            }
        }
    }

    func exportOriginalSettings() {
        guard let recovery, let data = recovery.originalData else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = recovery.suggestedFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func replaceSavedSettings() throws {
        do {
            try storage.replaceSavedSettings(with: config)
            recovery = nil
        } catch {
            recovery = storage.recovery
            throw error
        }
    }

    func selectMode(_ id: UUID) {
        guard let mode = config.modes.first(where: { $0.id == id }) else {
            NSLog("MacDial: cannot select a missing mode")
            return
        }
        cyclingUtility = nil
        if mode.kind == .volumeOutput {
            guard let onVolumeOutput else {
                NSLog("MacDial: volume output selector is not connected")
                return
            }
            onVolumeOutput(id)
            return
        }
        config.selectMode(id)
    }

    func selectNextMode() {
        var next = config
        let cursor = cyclingUtility.flatMap { $0.operatingID == config.currentMode.id ? $0.id : nil }
        next.selectNextMode(after: cursor)
        guard let id = next.currentModeID, next.enabledModes.contains(where: { $0.id == id }) else { return }
        selectMode(id)
        if next.modes.first(where: { $0.id == id })?.kind == .volumeOutput {
            cyclingUtility = (id, config.currentMode.id)
        }
    }
}
