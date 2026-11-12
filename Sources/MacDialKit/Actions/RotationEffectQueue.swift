import Foundation

protocol RotationEffectQueueCancellationObserver: AnyObject {
    func rotationEffectQueueDidCancelPending()
}

/// Delivers rotation effects in order, yielding between large bursts.
public final class RotationEffectQueue {
    private struct Auxiliary {
        let action: RotationAction
        let increasing: Bool
        var remaining: Int
    }

    private struct RotationWork {
        let binding: RotationBinding
        var effects: RotationEffects.Iterator
        let perform: ((RotationEffect) -> Void)?
        let onComplete: (() -> Void)?
        var auxiliary: Auxiliary?

        var isComplete: Bool { auxiliary == nil && effects.isExhausted }

        mutating func take(upTo limit: Int) -> (RotationEffect, Int)? {
            if auxiliary == nil {
                guard let effect = effects.next() else { return nil }
                if case let .auxiliary(action, increasing, repeatCount) = effect {
                    auxiliary = Auxiliary(action: action, increasing: increasing, remaining: repeatCount)
                } else {
                    return (effect, 1)
                }
            }
            guard var pending = auxiliary else { return nil }
            let count = min(pending.remaining, limit)
            pending.remaining -= count
            auxiliary = pending.remaining == 0 ? nil : pending
            return (.auxiliary(action: pending.action, increasing: pending.increasing, repeatCount: count), count)
        }
    }

    private enum Work {
        case rotation(RotationWork)
        case action(() -> Void)
    }

    // A normal report at the editor's maximum auxiliary speed fits in one pass.
    private static let batchSize = Int(Int8.min.magnitude) * Int(RotationBinding.auxiliarySpeedRange.upperBound)
    private static let maximumPendingEvents = UInt(batchSize * 8)
    private let scheduleNext: (@escaping () -> Void) -> Void
    private let perform: (RotationBinding, RotationEffect) -> Void
    private var work: [Work] = []
    private var head = 0
    private var pendingRotationEvents: UInt = 0
    private var mouseReleases: [ClickAction: () -> Void] = [:]
    private weak var cancellationObserver: RotationEffectQueueCancellationObserver?
    private var cancellationObserverID: ObjectIdentifier?
    private var isDraining = false
    private var isScheduled = false
    private var isCancelling = false
    private var scheduleVersion: UInt = 0

    /// `scheduleNext` must enqueue asynchronously on the same serial context as `enqueue`.
    public init(scheduleNext: @escaping (@escaping () -> Void) -> Void,
                perform: @escaping (RotationBinding, RotationEffect) -> Void) {
        self.scheduleNext = scheduleNext
        self.perform = perform
    }

    /// Calls `onComplete` after the final effect of an accepted, nonempty request,
    /// unless pending work is cancelled.
    @discardableResult
    public func enqueue(_ effects: RotationEffects, for binding: RotationBinding,
                        perform: ((RotationEffect) -> Void)? = nil,
                        onComplete: (() -> Void)? = nil) -> Bool {
        guard effects.count > 0 else { return true }
        let count = effects.eventCount
        guard count <= Self.maximumPendingEvents,
              pendingRotationEvents <= Self.maximumPendingEvents - count else {
            NSLog("MacDial: ignoring %@ rotation producing %@ events because it exceeds the output queue limit",
                  binding.action.rawValue, String(count))
            return false
        }
        pendingRotationEvents += count
        work.append(.rotation(RotationWork(binding: binding, effects: effects.makeIterator(),
                                           perform: perform, onComplete: onComplete)))
        startIfNeeded()
        return true
    }

    /// Preserves the order of non-rotation actions behind any pending rotation.
    public func enqueueAction(_ action: @escaping () -> Void) {
        work.append(.action(action))
        startIfNeeded()
    }

    /// Tracks delivered mouse-down events so cancellation can release them.
    public func enqueueMouseButton(_ button: ClickAction, down: Bool, perform: @escaping (Bool) -> Void) {
        guard button.isMouseButton else {
            NSLog("MacDial: ignoring a non-mouse action in the mouse event queue")
            return
        }
        enqueueAction { [weak self] in
            guard let self else { return }
            if down {
                let version = self.scheduleVersion
                perform(true)
                if self.scheduleVersion == version {
                    let previous = self.mouseReleases.updateValue({ perform(false) }, forKey: button)
                    withExtendedLifetime(previous) {}
                } else {
                    perform(false)
                }
            } else {
                self.mouseReleases.removeValue(forKey: button)
                perform(false)
            }
        }
    }

    func observeCancellation(_ observer: RotationEffectQueueCancellationObserver) -> Bool {
        guard cancellationObserverID == nil else { return false }
        cancellationObserverID = ObjectIdentifier(observer)
        cancellationObserver = observer
        return true
    }

    func stopObservingCancellation(_ observer: RotationEffectQueueCancellationObserver) {
        guard cancellationObserverID == ObjectIdentifier(observer) else { return }
        cancellationObserver = nil
        cancellationObserverID = nil
    }

    public func cancelPending() {
        let alreadyCancelling = isCancelling
        isCancelling = true
        defer {
            isCancelling = alreadyCancelling
            if !alreadyCancelling, !work.isEmpty { startIfNeeded() }
        }
        var cancelledWork = work
        work = []
        head = 0
        pendingRotationEvents = 0
        isScheduled = false
        scheduleVersion &+= 1
        let releases = Array(mouseReleases.values)
        mouseReleases.removeAll()
        cancellationObserver?.rotationEffectQueueDidCancelPending()
        for release in releases { release() }
        cancelledWork.removeAll()
    }

    private func startIfNeeded() {
        guard !isCancelling, !isDraining, !isScheduled else { return }
        drain()
    }

    private func drain() {
        isScheduled = false
        isDraining = true
        var remaining = Self.batchSize
        while remaining > 0, head < work.count {
            switch work[head] {
            case .action(let action):
                head += 1
                remaining -= 1
                action()
            case .rotation(var rotation):
                guard let (effect, cost) = rotation.take(upTo: remaining) else {
                    head += 1
                    continue
                }
                let isComplete = rotation.isComplete
                if isComplete {
                    head += 1
                } else {
                    work[head] = .rotation(rotation)
                }
                remaining -= cost
                pendingRotationEvents -= UInt(cost)
                let version = scheduleVersion
                if let perform = rotation.perform {
                    perform(effect)
                } else {
                    perform(rotation.binding, effect)
                }
                if isComplete, scheduleVersion == version {
                    rotation.onComplete?()
                }
            }
        }
        // Captured objects can enqueue more work from deinit; release them after
        // the array mutation and queue state updates have completed.
        let completedWork = Array(work.prefix(head))
        work.removeFirst(head)
        head = 0
        isDraining = false
        if !work.isEmpty {
            isScheduled = true
            scheduleVersion &+= 1
            let version = scheduleVersion
            scheduleNext { [weak self] in
                guard let self, self.isScheduled, self.scheduleVersion == version else { return }
                self.drain()
            }
        }
        withExtendedLifetime(completedWork) {}
    }
}
