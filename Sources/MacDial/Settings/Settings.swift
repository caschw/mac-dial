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

    @Published var config: DialConfig {
        didSet {
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
        config.selectMode(id)
    }

    func selectNextMode() {
        config.selectNextMode()
    }
}
