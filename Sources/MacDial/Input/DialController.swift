import Foundation
import Combine
import MacDialKit

/// Composes native input, core gesture interpretation, and presentation on the main run loop.
final class DialController {
    let device: DialDevice
    let settings: SettingsStore
    let actions: ActionEngine
    let radial: RadialMenuController
    let hud: HUDController
    let waker: BluetoothWaker

    private let gestures: GestureInterpreter
    private var cancellables = Set<AnyCancellable>()
    private var lastModeID: UUID?
    /// What the open radial menu was built from, so settings edits can close a stale menu.
    private var shownMenu: (modes: [DialMode], stepsPerRevolution: Int)?

    init(device: DialDevice, settings: SettingsStore, actions: ActionEngine,
         radial: RadialMenuController, hud: HUDController, waker: BluetoothWaker,
         scheduler: GestureScheduler) {
        self.device = device
        self.settings = settings
        self.actions = actions
        self.radial = radial
        self.hud = hud
        self.waker = waker
        gestures = GestureInterpreter(configuration: { settings.config }, scheduler: scheduler,
                                      actions: actions, menu: radial, buzz: { [weak device] in device?.buzz() })

        actions.settings = settings
        actions.onRadialMenu = { [weak self] in self?.showRadialMenu() }
        radial.onSelect = { [weak settings] mode in settings?.selectMode(mode.id) }
        device.onButton = { [weak self] state in
            if state == .pressed { self?.gestures.buttonDown() } else { self?.gestures.buttonUp() }
        }
        device.onRotate = { [weak self] delta in self?.gestures.rotate(delta) }

        lastModeID = settings.config.currentMode.id
        settings.$config
            .sink { [weak self] config in self?.apply(config) }
            .store(in: &cancellables)
    }

    private func apply(_ config: DialConfig) {
        if device.stepsPerRevolution != config.stepsPerRevolution {
            device.stepsPerRevolution = config.stepsPerRevolution
        }
        if device.detentHaptics != config.detentHaptics {
            device.detentHaptics = config.detentHaptics
        }
        waker.isEnabled = config.fastWake

        if radial.isVisible, let shownMenu,
           shownMenu.modes != config.enabledModes || shownMenu.stepsPerRevolution != config.stepsPerRevolution {
            radial.dismiss()
        }

        let mode = config.currentMode
        if mode.id != lastModeID {
            lastModeID = mode.id
            gestures.resetGesture()
            if config.menuHaptics { device.buzz() }
            if config.showHUD { hud.show(icon: mode.icon, title: mode.name) }
        }
    }

    func showRadialMenu() {
        let config = settings.config
        let modes = config.enabledModes
        guard !modes.isEmpty else { return }
        if config.menuHaptics { device.buzz(repeatCount: 1) }
        shownMenu = (modes, config.stepsPerRevolution)
        radial.show(modes: modes, selectedID: config.currentMode.id,
                    detentsPerItem: max(1, config.stepsPerRevolution / 18),
                    atCursor: config.radialAtCursor)
    }
}
