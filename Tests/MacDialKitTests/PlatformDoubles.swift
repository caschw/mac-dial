import Foundation
import MacDialKit

final class TestClock: GestureScheduler {
    final class Task: ScheduledGesture {
        let deadline: TimeInterval
        let action: () -> Void
        var cancelled = false
        init(deadline: TimeInterval, action: @escaping () -> Void) {
            self.deadline = deadline
            self.action = action
        }
        func cancel() { cancelled = true }
    }

    private(set) var now: TimeInterval = 0
    private var tasks: [Task] = []
    var pendingCount: Int { tasks.filter { !$0.cancelled }.count }

    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ScheduledGesture {
        let task = Task(deadline: now + interval, action: action)
        tasks.append(task)
        return task
    }

    func advance(by interval: TimeInterval) {
        let target = now + interval
        while let task = tasks.filter({ !$0.cancelled && $0.deadline <= target })
            .min(by: { $0.deadline < $1.deadline }) {
            now = task.deadline
            task.cancelled = true
            task.action()
        }
        now = target
        tasks.removeAll { $0.cancelled }
    }
}

final class SimulatedDial {
    enum ButtonState { case pressed, released }
    var onButton: ((ButtonState) -> Void)?
    var onRotate: ((Int) -> Void)?
}

final class TestConfiguration {
    var config = DialConfig()
}

final class RecordingActions: DialActions {
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

final class RecordingMenu: DialMenu {
    var isVisible = false
    var moves: [Int] = []
    var confirmations = 0
    var dismissals = 0
    var selectionChanged = true
    func move(by delta: Int) -> Bool { moves.append(delta); return selectionChanged }
    func confirm() { confirmations += 1 }
    func dismiss() { dismissals += 1; isVisible = false }
}

final class GestureHarness {
    let settings: TestConfiguration
    let clock = TestClock()
    let device = SimulatedDial()
    let actions = RecordingActions()
    let radial = RecordingMenu()
    private(set) var buzzes = 0
    private(set) var gestures: GestureInterpreter!

    init(settings: TestConfiguration = TestConfiguration()) {
        self.settings = settings
        gestures = GestureInterpreter(configuration: { settings.config }, scheduler: clock,
                                      actions: actions, menu: radial, buzz: { [weak self] in self?.buzzes += 1 })
        device.onButton = { [weak self] state in
            if state == .pressed { self?.gestures.buttonDown() } else { self?.gestures.buttonUp() }
        }
        device.onRotate = { [weak self] delta in self?.gestures.rotate(delta) }
    }
}
