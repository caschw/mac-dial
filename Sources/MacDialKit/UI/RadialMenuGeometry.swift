import CoreGraphics
import Foundation

/// A wedge of the dial, in degrees measured clockwise from twelve o'clock.
public struct RadialSector: Equatable {
    public let center: Double
    public let span: Double

    public init(center: Double, span: Double) {
        self.center = center
        self.span = span
    }

    public var start: Double { center - span / 2 }
    public var end: Double { center + span / 2 }
}

/// Deterministic geometry for the glass dial and its submenu arcs.
public enum RadialMenuGeometry {
    /// Equal wedges filling the root dial, the first centered at twelve o'clock.
    /// Returns an empty array for a non-positive count.
    public static func rootSectors(count: Int) -> [RadialSector] {
        guard count > 0 else { return [] }
        let span = 360 / Double(count)
        return (0..<count).map { RadialSector(center: Double($0) * span, span: span) }
    }

    /// The contiguous slots an arc shows, keeping the selection near the middle
    /// when there are more slots than fit. Returns nil for invalid input.
    public static func visibleWindow(slotCount: Int, selected: Int, maxVisible: Int) -> Range<Int>? {
        guard slotCount > 0, maxVisible > 0, (0..<slotCount).contains(selected) else { return nil }
        guard slotCount > maxVisible else { return 0..<slotCount }
        let first = min(max(selected - maxVisible / 2, 0), slotCount - maxVisible)
        return first..<(first + maxVisible)
    }

    /// Wedges for an arc of `count` slots, centered on `anchor` degrees.
    /// Returns an empty array when the input is invalid or would exceed a full turn.
    public static func arcSectors(anchor: Double, count: Int, slotSpan: Double) -> [RadialSector] {
        guard count > 0, anchor.isFinite, slotSpan.isFinite, slotSpan > 0,
              Double(count) * slotSpan <= 360 else { return [] }
        let first = anchor - Double(count - 1) * slotSpan / 2
        return (0..<count).map { RadialSector(center: first + Double($0) * slotSpan, span: slotSpan) }
    }

    /// Where to center a footprint so it stays inside `bounds`. Axes the footprint
    /// cannot fit are centered in `bounds`; non-finite input falls back to the
    /// center of `bounds`, or to `desired` when `bounds` itself is unusable.
    public static func clampedCenter(_ desired: CGPoint, footprint: CGSize, in bounds: CGRect) -> CGPoint {
        guard !bounds.isNull, !bounds.isInfinite, bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width.isFinite, bounds.height.isFinite else { return desired }
        let bounds = bounds.standardized
        func clamp(_ value: CGFloat, size: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
            let half = size.isFinite ? Swift.max(size, 0) / 2 : 0
            let low = lower + half, high = upper - half
            guard low <= high else { return (lower + upper) / 2 }
            guard value.isFinite else { return (lower + upper) / 2 }
            return Swift.min(Swift.max(value, low), high)
        }
        return CGPoint(x: clamp(desired.x, size: footprint.width, min: bounds.minX, max: bounds.maxX),
                       y: clamp(desired.y, size: footprint.height, min: bounds.minY, max: bounds.maxY))
    }
}
