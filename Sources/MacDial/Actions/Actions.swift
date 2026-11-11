import Foundation
import AppKit
import CoreGraphics
import MacDialKit

// MARK: - Low level event synthesis

enum InputSynth {
    // NX_KEYTYPE_* from IOKit/hidsystem/ev_keymap.h
    enum AuxKey: Int32 {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
        case play = 16, next = 17, previous = 18
    }

    // Virtual key codes (Carbon kVK_*)
    enum Key {
        static let tab: CGKeyCode = 0x30
        static let command: CGKeyCode = 0x37
        static let z: CGKeyCode = 0x06
        static let equal: CGKeyCode = 0x18
        static let minus: CGKeyCode = 0x1B
        static let left: CGKeyCode = 0x7B
        static let right: CGKeyCode = 0x7C
        static let down: CGKeyCode = 0x7D
        static let up: CGKeyCode = 0x7E
    }

    private static let source = CGEventSource(stateID: .hidSystemState)

    /// Media / brightness keys. https://stackoverflow.com/a/55854051
    static func postAuxKey(_ key: AuxKey, modifiers: NSEvent.ModifierFlags = [], repeatCount: Int = 1) {
        func post(down: Bool) {
            let state: UInt = down ? 0xa00 : 0xb00
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: state | modifiers.rawValue),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int((key.rawValue << 16) | Int32(state)),
                data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        for _ in 0..<max(1, repeatCount) {
            post(down: true)
            post(down: false)
        }
    }

    static func cgFlags(_ flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.function) { result.insert(.maskSecondaryFn) }
        return result
    }

    static func postKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        var flags = flags
        // Real arrow keys carry these flags; system hotkeys like ⌃← (switch
        // Space) only match when they are present.
        if (Key.left...Key.up).contains(code) {
            flags.insert(.maskSecondaryFn)
            flags.insert(.maskNumericPad)
        }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    static func postKeyState(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    static func post(_ shortcut: KeyShortcut) {
        postKey(CGKeyCode(shortcut.keyCode), flags: cgFlags(shortcut.modifierFlags))
    }

    static var cursorLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    enum MouseButton { case left, right, middle }

    static func postMouse(_ button: MouseButton, down: Bool, clickCount: Int64 = 1) {
        let type: CGEventType
        let cgButton: CGMouseButton
        switch button {
        case .left: type = down ? .leftMouseDown : .leftMouseUp; cgButton = .left
        case .right: type = down ? .rightMouseDown : .rightMouseUp; cgButton = .right
        case .middle: type = down ? .otherMouseDown : .otherMouseUp; cgButton = .center
        }
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: cursorLocation, mouseButton: cgButton)
        event?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event?.post(tap: .cghidEventTap)
    }

    static func click(_ button: MouseButton) {
        postMouse(button, down: true)
        postMouse(button, down: false)
    }

    static func doubleClick() {
        for count in Int64(1)...2 {
            postMouse(.left, down: true, clickCount: count)
            postMouse(.left, down: false, clickCount: count)
        }
    }

    static func scroll(vertical: Int32, horizontal: Int32) {
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                            wheel1: vertical, wheel2: horizontal, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }
}

// MARK: - Action engine

/// Executes the configured action for a rotation or click gesture.
final class ActionEngine: DialActions {
    weak var settings: SettingsStore?
    var onRadialMenu: (() -> Void)?

    private let rotation = RotationInterpreter()
    private let scheduler: GestureScheduler
    private var appSwitchReleaseTimer: Timer?
    private var appSwitcherActive = false

    init(scheduler: GestureScheduler) {
        self.scheduler = scheduler
    }

    // MARK: Rotation

    func rotate(_ binding: RotationBinding, delta: Int) {
        for effect in rotation.rotate(binding, delta: delta, at: scheduler.now) {
            switch effect {
            case let .scroll(vertical, horizontal):
                InputSynth.scroll(vertical: vertical, horizontal: horizontal)
            case let .auxiliary(action, increasing, repeatCount):
                let key: InputSynth.AuxKey = action == .volume
                    ? (increasing ? .soundUp : .soundDown)
                    : (increasing ? .brightnessUp : .brightnessDown)
                InputSynth.postAuxKey(key, modifiers: [.shift, .option], repeatCount: repeatCount)
            case let .discrete(forward):
                discrete(binding, forward: forward)
            }
        }
    }

    private func discrete(_ binding: RotationBinding, forward: Bool) {
        typealias K = InputSynth.Key
        switch binding.action {
        case .switchDesktops:
            InputSynth.postKey(forward ? K.right : K.left, flags: .maskControl)
        case .zoom:
            InputSynth.postKey(forward ? K.equal : K.minus, flags: .maskCommand)
        case .undoRedo:
            InputSynth.postKey(K.z, flags: forward ? [.maskCommand, .maskShift] : .maskCommand)
        case .switchTabs:
            InputSynth.postKey(K.tab, flags: forward ? .maskControl : [.maskControl, .maskShift])
        case .switchApps:
            switchApp(forward: forward)
        case .mediaTracks:
            InputSynth.postAuxKey(forward ? .next : .previous)
        case .arrowsHorizontal:
            InputSynth.postKey(forward ? K.right : K.left)
        case .arrowsVertical:
            InputSynth.postKey(forward ? K.down : K.up)
        case .customShortcut:
            if let shortcut = forward ? binding.clockwise : binding.counterClockwise {
                InputSynth.post(shortcut)
            }
        default:
            break
        }
    }

    /// Holds ⌘ while the dial turns so the app switcher stays open, then
    /// releases it shortly after the dial stops (or on click).
    private func switchApp(forward: Bool) {
        typealias K = InputSynth.Key
        if !appSwitcherActive {
            appSwitcherActive = true
            InputSynth.postKeyState(K.command, down: true, flags: .maskCommand)
        }
        InputSynth.postKeyState(K.tab, down: true, flags: forward ? .maskCommand : [.maskCommand, .maskShift])
        InputSynth.postKeyState(K.tab, down: false, flags: forward ? .maskCommand : [.maskCommand, .maskShift])
        appSwitchReleaseTimer?.invalidate()
        appSwitchReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            self?.finishAppSwitch()
        }
    }

    /// Returns true if a pending app switch was committed.
    @discardableResult
    func finishAppSwitch() -> Bool {
        appSwitchReleaseTimer?.invalidate()
        appSwitchReleaseTimer = nil
        guard appSwitcherActive else { return false }
        appSwitcherActive = false
        InputSynth.postKeyState(InputSynth.Key.command, down: false, flags: [])
        return true
    }

    // MARK: Clicks

    func perform(_ binding: ClickBinding) {
        switch binding.action {
        case .none: break
        case .leftClick: InputSynth.click(.left)
        case .rightClick: InputSynth.click(.right)
        case .middleClick: InputSynth.click(.middle)
        case .doubleLeftClick: InputSynth.doubleClick()
        case .playPause: InputSynth.postAuxKey(.play)
        case .mute: InputSynth.postAuxKey(.mute)
        case .nextTrack: InputSynth.postAuxKey(.next)
        case .previousTrack: InputSynth.postAuxKey(.previous)
        case .missionControl: openMissionControl(arguments: [])
        case .showDesktop: openMissionControl(arguments: ["1"])
        case .appExpose: openMissionControl(arguments: ["2"])
        case .radialMenu: onRadialMenu?()
        case .nextMode: settings?.selectNextMode()
        case .customShortcut:
            if let shortcut = binding.shortcut { InputSynth.post(shortcut) }
        case .openApp:
            if let path = binding.appPath {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                                   configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        }
    }

    /// Press and hold for mouse buttons, so the dial can drag things.
    func mouse(_ action: ClickAction, down: Bool) {
        switch action {
        case .leftClick: InputSynth.postMouse(.left, down: down)
        case .rightClick: InputSynth.postMouse(.right, down: down)
        case .middleClick: InputSynth.postMouse(.middle, down: down)
        default: if !down { perform(ClickBinding(action)) }
        }
    }

    private func openMissionControl(arguments: [String]) {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = arguments
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
    }
}
