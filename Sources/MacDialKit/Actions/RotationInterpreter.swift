import Foundation

public enum RotationEffect: Equatable {
    case scroll(vertical: Int32, horizontal: Int32)
    case auxiliary(action: RotationAction, increasing: Bool, repeatCount: Int)
    case discrete(forward: Bool)
}

/// A lazy sequence so large aggregate deltas do not allocate one element per detent.
public struct RotationEffects: Sequence {
    public struct Iterator: IteratorProtocol {
        private let effect: RotationEffect?
        private var remaining: UInt

        fileprivate init(effect: RotationEffect?, count: UInt) {
            self.effect = effect
            self.remaining = count
        }

        var isExhausted: Bool { remaining == 0 }

        public mutating func next() -> RotationEffect? {
            guard remaining > 0 else { return nil }
            remaining -= 1
            return effect
        }
    }

    private let effect: RotationEffect?
    public let count: UInt

    var eventCount: UInt {
        if case let .auxiliary(_, _, repeatCount) = effect {
            return UInt(repeatCount)
        }
        return count
    }

    var isDiscrete: Bool {
        if case .discrete = effect { return true }
        return false
    }

    fileprivate init(_ effect: RotationEffect? = nil, count: UInt = 0) {
        self.effect = effect
        self.count = count
    }

    public func makeIterator() -> Iterator {
        Iterator(effect: effect, count: count)
    }
}

/// Selects rotation effects without generating system input.
public final class RotationInterpreter {
    private var accumulator = 0
    private var accumulatorIsForward = true
    private var lastRotation: TimeInterval?
    private var lastBindingKey = ""

    public init() {}

    /// Offers a rotation to an output queue, restoring selection state on rejection.
    /// A rejecting callback must not deliver effects or reenter this interpreter.
    @discardableResult
    public func rotate(_ binding: RotationBinding, delta: Int, at now: TimeInterval,
                       enqueue: (RotationEffects) -> Bool) -> Bool {
        let previous = (accumulator, accumulatorIsForward, lastRotation, lastBindingKey)
        let effects = rotate(binding, delta: delta, at: now)
        guard enqueue(effects) else {
            (accumulator, accumulatorIsForward, lastRotation, lastBindingKey) = previous
            return false
        }
        return true
    }

    /// Accepts both individual HID deltas and aggregate detent counts.
    public func rotate(_ binding: RotationBinding, delta: Int, at now: TimeInterval) -> RotationEffects {
        guard binding.action != .none, delta != 0 else { return RotationEffects() }
        guard now.isFinite else {
            NSLog("MacDial: ignoring rotation with a nonfinite timestamp")
            return RotationEffects()
        }
        let difference = lastRotation.map { now - $0 } ?? .infinity
        let elapsed = difference >= 0 ? difference : .infinity
        let forward = (delta > 0) != binding.reversed
        let magnitude = delta.magnitude

        if binding.action.isContinuous {
            guard binding.speed.isFinite, binding.speed >= 0 else {
                NSLog("MacDial: ignoring rotation with an invalid speed")
                return RotationEffects()
            }
            let effect: RotationEffect
            switch binding.action {
            case .scrollVertical, .scrollHorizontal:
                let ms = min(elapsed * 1000, 150)
                let acceleration = 1 + (150 - ms) / 40
                let direction = forward ? Double(magnitude) : -Double(magnitude)
                let distance = (-direction * 14 * binding.speed * acceleration).rounded()
                guard let pixels = Int32(exactly: distance) else {
                    NSLog("MacDial: ignoring scroll distance outside the system event range")
                    return RotationEffects()
                }
                effect = .scroll(vertical: binding.action == .scrollVertical ? pixels : 0,
                                 horizontal: binding.action == .scrollHorizontal ? pixels : 0)
            case .volume, .brightness:
                guard let roundedSpeed = Int(exactly: binding.speed.rounded()) else {
                    NSLog("MacDial: ignoring an unrepresentable auxiliary step size")
                    return RotationEffects()
                }
                let repetitions = max(1, roundedSpeed)
                let (total, overflow) = magnitude.multipliedReportingOverflow(by: UInt(repetitions))
                guard !overflow, let repeatCount = Int(exactly: total) else {
                    NSLog("MacDial: ignoring an unrepresentable auxiliary event count")
                    return RotationEffects()
                }
                effect = .auxiliary(action: binding.action, increasing: forward, repeatCount: repeatCount)
            default:
                return RotationEffects()
            }
            lastRotation = now
            return RotationEffects(effect, count: 1)
        }

        // Preserve the existing threshold, pause, and direction-change policy.
        let key = "\(binding.action.rawValue)-\(binding.stepsPerAction)"
        if key != lastBindingKey || elapsed > 0.8 || (accumulator != 0 && accumulatorIsForward != forward) {
            accumulator = 0
            lastBindingKey = key
        }
        let steps = max(1, binding.stepsPerAction)
        let sum = UInt(accumulator) + magnitude
        let count = sum / UInt(steps)
        accumulator = Int(sum % UInt(steps))
        accumulatorIsForward = forward
        lastRotation = now
        return RotationEffects(.discrete(forward: forward), count: count)
    }
}
