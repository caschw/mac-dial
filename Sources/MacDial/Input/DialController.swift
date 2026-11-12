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
    let audio: AudioOutputService

    private let gestures: GestureInterpreter
    private var cancellables = Set<AnyCancellable>()
    private var lastModeID: UUID?
    /// What the open radial menu was built from, so settings edits can close a stale menu.
    private var shownMenu: (modes: [DialMode], stepsPerRevolution: Int)?
    private var requestedOutputModeID: UUID?

    init(device: DialDevice, settings: SettingsStore, actions: ActionEngine,
         radial: RadialMenuController, hud: HUDController, waker: BluetoothWaker,
         scheduler: GestureScheduler, audio: AudioOutputService) {
        self.device = device
        self.settings = settings
        self.actions = actions
        self.radial = radial
        self.hud = hud
        self.waker = waker
        self.audio = audio
        gestures = GestureInterpreter(configuration: { settings.config }, scheduler: scheduler,
                                      actions: actions, menu: radial, buzz: { [weak device] in device?.buzz() })

        actions.settings = settings
        actions.onRadialMenu = { [weak self] in self?.showRadialMenu() }
        settings.onVolumeOutput = { [weak self] id in self?.showRadialMenu(outputModeID: id) }
        radial.onSelect = { [weak self] choice in self?.select(choice) ?? false }
        audio.onError = { [weak hud] message in hud?.show(icon: "exclamationmark.triangle", title: message) }
        device.onButton = { [weak self] state in
            if state == .pressed { self?.gestures.buttonDown() } else { self?.gestures.buttonUp() }
        }
        device.onRotate = { [weak self] delta in self?.gestures.rotate(delta) }

        lastModeID = settings.config.currentMode.id
        settings.$config
            .sink { [weak self] config in self?.apply(config) }
            .store(in: &cancellables)
        audio.$outputs.combineLatest(audio.$error)
            .sink { [weak self] outputs, error in
                guard let self, self.radial.isVisible else { return }
                self.refreshMenu(self.settings.config, outputs: outputs, error: error)
            }
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
        if radial.isVisible { refreshMenu(config, outputs: audio.outputs, error: audio.error) }

        let mode = config.currentMode
        if mode.id != lastModeID {
            lastModeID = mode.id
            gestures.resetGesture()
            if config.menuHaptics { device.buzz() }
            if config.showHUD { hud.show(icon: mode.icon, title: mode.name) }
        }
    }

    func showRadialMenu(outputModeID: UUID? = nil) {
        if outputModeID != nil { gestures.resetGesture() }
        requestedOutputModeID = outputModeID
        audio.refresh()
        let config = settings.config
        let modes = menuModes(config)
        guard !modes.isEmpty else { return }
        if config.menuHaptics { device.buzz(repeatCount: 1) }
        shownMenu = (config.enabledModes, config.stepsPerRevolution)
        let items = AudioOutputMenu.items(modes: modes, outputs: audio.outputs, preferences: config.audioOutput,
                                         error: audio.error)
        radial.show(items: items, selectedID: (outputModeID ?? config.currentMode.id).uuidString,
                    detentsPerItem: max(1, config.stepsPerRevolution / 18), atCursor: config.radialAtCursor,
                    enterGroup: outputModeID != nil,
                    preferredOutputUID: config.audioOutput.selectedUID)
    }

    private func refreshMenu(_ config: DialConfig, outputs: [AudioOutput], error: String?) {
        radial.replaceItems(AudioOutputMenu.items(modes: menuModes(config), outputs: outputs,
                                                 preferences: config.audioOutput, error: error))
    }

    private func menuModes(_ config: DialConfig) -> [DialMode] {
        AudioOutputMenu.modes(for: config, requestedOutputModeID: requestedOutputModeID)
    }

    private func select(_ choice: DialMenuChoice) -> Bool {
        switch choice {
        case .mode(let mode):
            settings.selectMode(mode.id)
            return true
        case .information(let message):
            hud.show(icon: "speaker.slash", title: message)
            return false
        case .systemDefaultAudioOutput:
            settings.config.audioOutput.selectedUID = nil
            gestures.resetGesture()
            if settings.config.showHUD {
                let confirmation = AudioOutputMenu.confirmation(for: nil)
                hud.show(icon: confirmation.symbol, title: confirmation.title)
            }
            return true
        case .audioOutput(let uid):
            do {
                let output = try audio.select(uid, preferences: settings.config.audioOutput)
                settings.config.audioOutput.selectedUID = output.uid
                gestures.resetGesture()
                if settings.config.showHUD {
                    let confirmation = AudioOutputMenu.confirmation(for: output)
                    hud.show(icon: confirmation.symbol, title: confirmation.title)
                }
                return true
            } catch {
                NSLog("MacDial: cannot select volume output: %@", error.localizedDescription)
                hud.show(icon: "exclamationmark.triangle", title: error.localizedDescription)
                return false
            }
        }
    }
}
