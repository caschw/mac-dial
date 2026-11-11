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
    private static let key = "dialConfig.v2"

    @Published var config: DialConfig {
        didSet {
            guard config != oldValue else { return }
            if let data = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(data, forKey: SettingsStore.key)
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: SettingsStore.key),
           let saved = try? JSONDecoder().decode(DialConfig.self, from: data) {
            config = saved
        } else {
            config = DialConfig()
        }
        if config.modes.isEmpty { config.modes = DialMode.defaults }
    }

    func selectMode(_ id: UUID) {
        config.selectMode(id)
    }

    func selectNextMode() {
        config.selectNextMode()
    }
}
