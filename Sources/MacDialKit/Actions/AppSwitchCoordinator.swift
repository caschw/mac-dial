import Foundation

/// Orders app-switch keys and associates release timers with the requesting rotation.
/// Use and release the coordinator on the output queue's serial context.
/// A queued commit retains its coordinator until the queue drains or is cancelled.
public final class AppSwitchCoordinator: RotationEffectQueueCancellationObserver {
    private final class Request {}

    private let output: RotationEffectQueue
    private let scheduler: GestureScheduler
    private let postCommand: (Bool) -> Void
    private let postTab: (Bool) -> Void
    private var requested: Request?
    private var timerRequest: Request?
    private var releaseTimer: ScheduledGesture?
    private var commandIsDown = false
    private var isShutDown = false

    /// Returns nil if the output queue already has an app-switch coordinator.
    public init?(output: RotationEffectQueue, scheduler: GestureScheduler,
                 postCommand: @escaping (Bool) -> Void, postTab: @escaping (Bool) -> Void) {
        self.output = output
        self.scheduler = scheduler
        self.postCommand = postCommand
        self.postTab = postTab
        guard output.observeCancellation(self) else {
            NSLog("MacDial: refusing multiple app-switch coordinators for one output queue")
            return nil
        }
    }

    deinit {
        cancelReleaseTimer()
        releaseCommand()
        output.stopObservingCancellation(self)
    }

    @discardableResult
    public func enqueue(_ effects: RotationEffects, for binding: RotationBinding) -> Bool {
        guard !isShutDown, binding.action == .switchApps else {
            NSLog("MacDial: ignoring an invalid app-switch request")
            return false
        }
        guard effects.count > 0 else { return true }
        guard effects.isDiscrete else {
            NSLog("MacDial: ignoring a non-discrete app-switch effect")
            return false
        }

        let previous = requested
        let request = Request()
        requested = request
        let accepted = output.enqueue(effects, for: binding, perform: { [weak self] effect in
            guard case let .discrete(forward) = effect else {
                NSLog("MacDial: ignoring a non-discrete app-switch effect")
                return
            }
            self?.switchApp(forward: forward)
        }, onComplete: { [weak self] in
            guard let self, self.commandIsDown, self.requested === request else { return }
            self.scheduleRelease(for: request)
        })
        if !accepted {
            requested = previous
        } else if requested === request, timerRequest !== request {
            cancelReleaseTimer()
        }
        return accepted
    }

    /// Returns true when a requested switch was committed.
    @discardableResult
    public func finish() -> Bool {
        guard requested != nil else { return false }
        requested = nil
        let timer = releaseTimer
        releaseTimer = nil
        timerRequest = nil
        output.enqueueAction { self.releaseCommand() }
        timer?.cancel()
        return true
    }

    /// Cancels pending output and balances any delivered Command-down.
    public func shutdown() {
        isShutDown = true
        output.cancelPending()
    }

    private func switchApp(forward: Bool) {
        if !commandIsDown {
            commandIsDown = true
            postCommand(true)
            guard commandIsDown else { return }
        }
        postTab(forward)
    }

    private func scheduleRelease(for request: Request) {
        cancelReleaseTimer()
        var fired = false
        let timer = scheduler.schedule(after: 0.9) { [weak self] in
            fired = true
            guard let self, self.requested === request else { return }
            self.finish()
        }
        if !fired, requested === request {
            releaseTimer = timer
            timerRequest = request
        } else {
            timer.cancel()
        }
    }

    func rotationEffectQueueDidCancelPending() {
        requested = nil
        cancelReleaseTimer()
        releaseCommand()
    }

    private func cancelReleaseTimer() {
        let timer = releaseTimer
        releaseTimer = nil
        timerRequest = nil
        timer?.cancel()
    }

    private func releaseCommand() {
        guard commandIsDown else { return }
        commandIsDown = false
        postCommand(false)
    }
}
