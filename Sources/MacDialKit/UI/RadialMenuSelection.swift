/// Tracks radial-menu movement without depending on its presentation.
public struct RadialMenuSelection {
    public private(set) var selected: Int
    public private(set) var continuousSelection: Int

    private let itemCount: Int
    private let detentsPerItem: Int
    private var remainder = 0

    public init?(itemCount: Int, selected: Int, detentsPerItem: Int) {
        guard itemCount > 0, selected >= 0, selected < itemCount, detentsPerItem > 0 else { return nil }
        self.itemCount = itemCount
        self.detentsPerItem = detentsPerItem
        self.selected = selected
        self.continuousSelection = selected
    }

    /// Forgets detents that have not yet crossed a selection step.
    public mutating func discardPartialMovement() {
        remainder = 0
    }

    /// Returns true if at least one selection step was crossed.
    @discardableResult
    public mutating func move(by delta: Int) -> Bool {
        guard delta != 0 else { return false }

        let magnitude: UInt
        let forward: Bool
        if remainder == 0 {
            magnitude = delta.magnitude
            forward = delta > 0
        } else if (remainder > 0) == (delta > 0) {
            magnitude = remainder.magnitude + delta.magnitude
            forward = delta > 0
        } else if remainder.magnitude >= delta.magnitude {
            magnitude = remainder.magnitude - delta.magnitude
            forward = remainder > 0
        } else {
            magnitude = delta.magnitude - remainder.magnitude
            forward = delta > 0
        }

        let steps = magnitude / UInt(detentsPerItem)
        let left = Int(magnitude % UInt(detentsPerItem))
        remainder = forward ? left : -left
        guard steps > 0 else { return false }

        let movement = forward ? Int(steps) : (steps == Int.min.magnitude ? Int.min : -Int(steps))
        let offset = movement % itemCount
        if offset >= 0 {
            let distanceToEnd = itemCount - selected
            selected = offset >= distanceToEnd ? offset - distanceToEnd : selected + offset
        } else {
            let distance = -offset
            selected = distance > selected ? itemCount - (distance - selected) : selected - distance
        }
        let (continuous, overflow) = continuousSelection.addingReportingOverflow(movement)
        continuousSelection = overflow ? selected : continuous
        return true
    }
}
