import Foundation

// Temporary characterization adapters: these never open devices or windows.
final class DialDevice {
    enum ButtonState { case pressed, released }
    var onButton: ((ButtonState) -> Void)?
    var onRotate: ((Int) -> Void)?
    var stepsPerRevolution = 36
    var detentHaptics = true
    func buzz(repeatCount: Int = 0) {}
}

final class ActionEngine {
    weak var settings: SettingsStore?
    var onRadialMenu: (() -> Void)?
    var performed: [ClickBinding] = []
    var rotations: [(RotationBinding, Int)] = []
    var mouseEvents: [(ClickAction, Bool)] = []
    var switchPending = false
    func perform(_ binding: ClickBinding) { performed.append(binding) }
    func rotate(_ binding: RotationBinding, delta: Int) { rotations.append((binding, delta)) }
    func mouse(_ action: ClickAction, down: Bool) { mouseEvents.append((action, down)) }
    func finishAppSwitch() -> Bool {
        defer { switchPending = false }
        return switchPending
    }
}

final class RadialMenuController {
    var onSelect: ((DialMode) -> Void)?
    var isVisible = false
    var moves: [Int] = []
    var confirmations = 0
    func move(by delta: Int) -> Bool { moves.append(delta); return true }
    func confirm() { confirmations += 1 }
    func dismiss() { isVisible = false }
    func show(modes: [DialMode], selectedID: UUID, detentsPerItem: Int, atCursor: Bool) { isVisible = true }
}

final class HUDController {
    func show(icon: String, title: String) {}
}

final class BluetoothWaker {
    var isEnabled = false
}
