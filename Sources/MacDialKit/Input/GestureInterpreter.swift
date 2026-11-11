import Foundation

/// Turns raw dial input into gestures (click, double click, press & hold,
/// rotate, rotate while pressed) and dispatches them to the current mode.
public final class GestureInterpreter {
    private let configuration: () -> DialConfig
    private let scheduler: GestureScheduler
    private let actions: DialActions
    private let radial: DialMenu
    private let buzz: () -> Void

    // Gesture state
    private var pressed = false
    private var passthroughButton: ClickAction?
    private var swallowRelease = false
    private var rotatedWhilePressed = false
    private var longPressTimer: ScheduledGesture?
    private var clickTimer: ScheduledGesture?

    private var config: DialConfig { configuration() }

    public init(configuration: @escaping () -> DialConfig, scheduler: GestureScheduler,
                actions: DialActions, menu: DialMenu, buzz: @escaping () -> Void) {
        self.configuration = configuration
        self.scheduler = scheduler
        self.actions = actions
        self.radial = menu
        self.buzz = buzz
    }

    deinit {
        longPressTimer?.cancel()
        clickTimer?.cancel()
    }

    // MARK: - Gestures

    public func buttonDown() {
        rotatedWhilePressed = false
        swallowRelease = false

        // A click while ⌘⇥ is held picks the highlighted app.
        if actions.finishAppSwitch() {
            swallowRelease = true
            pressed = true
            return
        }

        if radial.isVisible {
            pressed = true
            startLongPress { [weak self] in self?.radial.dismiss() }
            return
        }

        let mode = config.currentMode
        // Plain mouse-button modes get true press & hold, so you can drag.
        if mode.click.action.isMouseButton, mode.doubleClick.action == .none,
           mode.longPress.action == .none, mode.pressedRotate.action == .none {
            passthroughButton = mode.click.action
            actions.mouse(mode.click.action, down: true)
            return
        }

        pressed = true
        if mode.longPress.action != .none {
            startLongPress { [weak self] in
                guard let self else { return }
                if self.config.menuHaptics && mode.longPress.action != .radialMenu { self.buzz() }
                self.actions.perform(self.config.currentMode.longPress)
            }
        }
    }

    public func buttonUp() {
        if let button = passthroughButton {
            passthroughButton = nil
            actions.mouse(button, down: false)
            return
        }
        guard pressed else { return }
        pressed = false
        cancelLongPress()
        if swallowRelease || rotatedWhilePressed {
            swallowRelease = false
            return
        }

        if radial.isVisible {
            radial.confirm()
            return
        }

        let mode = config.currentMode
        guard mode.doubleClick.action != .none else {
            actions.perform(mode.click)
            return
        }
        if let timer = clickTimer {
            timer.cancel()
            clickTimer = nil
            actions.perform(mode.doubleClick)
        } else {
            clickTimer = scheduler.schedule(after: config.doubleClickInterval) { [weak self] in
                guard let self else { return }
                self.clickTimer = nil
                self.actions.perform(self.config.currentMode.click)
            }
        }
    }

    public func rotate(_ delta: Int) {
        if pressed || passthroughButton != nil {
            rotatedWhilePressed = true
            cancelLongPress()
        }
        if radial.isVisible {
            if radial.move(by: delta) && config.menuHaptics && !config.detentHaptics {
                buzz()
            }
            return
        }
        let mode = config.currentMode
        if pressed && mode.pressedRotate.action != .none {
            actions.rotate(mode.pressedRotate, delta: delta)
        } else {
            actions.rotate(mode.rotate, delta: delta)
        }
    }

    private func startLongPress(_ action: @escaping () -> Void) {
        cancelLongPress()
        longPressTimer = scheduler.schedule(after: config.longPressDuration) { [weak self] in
            guard let self, self.pressed, !self.rotatedWhilePressed else { return }
            self.longPressTimer = nil
            self.swallowRelease = true
            action()
        }
    }

    private func cancelLongPress() {
        longPressTimer?.cancel()
        longPressTimer = nil
    }

    /// Cancels pending actions when changing modes; an active mouse drag still receives its release.
    public func resetGesture() {
        cancelLongPress()
        clickTimer?.cancel()
        clickTimer = nil
    }
}
