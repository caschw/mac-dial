import Foundation

public enum RotationEffect: Equatable {
    case scroll(vertical: Int32, horizontal: Int32)
    case auxiliary(action: RotationAction, increasing: Bool, repeatCount: Int)
    case discrete(forward: Bool)
}

/// Selects rotation effects without generating system input.
public final class RotationInterpreter {
    private var accumulator = 0
    private var lastRotation = -Double.greatestFiniteMagnitude
    private var lastBindingKey = ""

    public init() {}

    public func rotate(_ binding: RotationBinding, delta: Int, at now: TimeInterval) -> [RotationEffect] {
        guard binding.action != .none, delta != 0 else { return [] }
        let elapsed = now - lastRotation
        lastRotation = now
        let direction = binding.reversed ? -delta : delta

        if binding.action.isContinuous {
            switch binding.action {
            case .scrollVertical, .scrollHorizontal:
                let ms = min(elapsed * 1000, 150)
                let acceleration = 1 + (150 - ms) / 40
                let pixels = Int32((Double(direction) * 14 * binding.speed * acceleration).rounded())
                return [.scroll(vertical: binding.action == .scrollVertical ? -pixels : 0,
                                horizontal: binding.action == .scrollHorizontal ? -pixels : 0)]
            case .volume, .brightness:
                return [.auxiliary(action: binding.action, increasing: direction > 0,
                                   repeatCount: abs(direction) * max(1, Int(binding.speed.rounded())))]
            default:
                return []
            }
        }

        // Preserve the existing threshold, pause, and direction-change policy.
        let key = "\(binding.action.rawValue)-\(binding.stepsPerAction)"
        if key != lastBindingKey || elapsed > 0.8 || (accumulator != 0 && (accumulator > 0) != (direction > 0)) {
            accumulator = 0
            lastBindingKey = key
        }
        accumulator += direction
        let steps = max(1, binding.stepsPerAction)
        var effects: [RotationEffect] = []
        while abs(accumulator) >= steps {
            let sign = accumulator > 0 ? 1 : -1
            effects.append(.discrete(forward: sign > 0))
            accumulator -= sign * steps
        }
        return effects
    }
}
