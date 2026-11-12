import SwiftUI
import MacDialKit

// MARK: - Shape

/// A ring segment between two radii, with angles in degrees clockwise from twelve o'clock.
struct AnnularSector: Shape {
    var startDegrees: Double
    var endDegrees: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startDegrees, endDegrees) }
        set { (startDegrees, endDegrees) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // SwiftUI measures from three o'clock in a y-down space, so `clockwise: false`
        // draws clockwise on screen.
        let start = Angle.degrees(startDegrees - 90), end = Angle.degrees(endDegrees - 90)
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// One contour prevents separate glass edges from opening a seam at the submenu join.
struct DialOutline: Shape {
    let arc: GlassDialArc?

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = GlassDialView.diameter / 2
        let sectors = arc.map {
            RadialMenuGeometry.arcSectors(anchor: $0.anchor, count: $0.slots.count,
                                         slotSpan: GlassDialView.arcSlotSpan)
        } ?? []
        guard let first = sectors.first, let last = sectors.last else {
            return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                         width: radius * 2, height: radius * 2))
        }

        var path = Path()
        path.addArc(center: center, radius: GlassDialView.arcOuterRadius,
                    startAngle: .degrees(first.start - 90), endAngle: .degrees(last.end - 90),
                    clockwise: false)
        let join = polarOffset(degrees: last.end, radius: radius)
        path.addLine(to: CGPoint(x: center.x + join.width, y: center.y + join.height))
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(last.end - 90), endAngle: .degrees(first.start + 270),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct RadialDividers: Shape {
    let angles: [Double]
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for angle in angles {
            let inner = polarOffset(degrees: angle, radius: innerRadius)
            let outer = polarOffset(degrees: angle, radius: outerRadius)
            path.move(to: CGPoint(x: rect.midX + inner.width, y: rect.midY + inner.height))
            path.addLine(to: CGPoint(x: rect.midX + outer.width, y: rect.midY + outer.height))
        }
        return path
    }
}

private struct SelectionArc: Shape {
    var startDegrees: Double
    var endDegrees: Double
    let radius: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startDegrees, endDegrees) }
        set { (startDegrees, endDegrees) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if endDegrees - startDegrees >= 360 {
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
        } else if endDegrees > startDegrees {
            path.addArc(center: center, radius: radius, startAngle: .degrees(startDegrees - 90),
                        endAngle: .degrees(endDegrees - 90), clockwise: false)
        }
        return path
    }
}

// MARK: - Presentation model

struct GlassDialSlot: Identifiable, Equatable {
    enum Kind: Equatable { case leaf, group, back }

    let id: String
    let title: String
    let symbol: String
    let kind: Kind

    static let back = GlassDialSlot(id: "glass-dial.back", title: "Back", symbol: "arrow.uturn.backward",
                                    kind: .back)

    init(id: String, title: String, symbol: String, kind: Kind) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.kind = kind
    }

    init<Payload>(_ slot: RadialMenuSlot<Payload>) {
        guard let item = slot.item else {
            self = .back
            return
        }
        self.init(id: item.id, title: item.title, symbol: item.symbol, kind: item.isGroup ? .group : .leaf)
    }
}

/// The visible part of the active submenu.
struct GlassDialArc: Equatable {
    /// Identifies the submenu so a new level animates in rather than morphing.
    var id: String
    var anchor: Double
    var slots: [GlassDialSlot]
    var selected: Int
    var hasMoreBefore: Bool
    var hasMoreAfter: Bool
}

/// Snapshot of `RadialMenuNavigation` for the views. Only one outer arc is shown at a time.
final class GlassDialModel: ObservableObject {
    @Published var rootSlots: [GlassDialSlot] = []
    @Published var rootSelected = 0
    /// Unwrapped selection so the highlight animates the short way round.
    @Published var rootContinuousSelection = 0
    @Published var arc: GlassDialArc?
    @Published var breadcrumb: [String] = []

    static let maxVisibleArcSlots = 7

    init() {}

    init(rootSlots: [GlassDialSlot], rootSelected: Int, arc: GlassDialArc? = nil, breadcrumb: [String] = []) {
        self.rootSlots = rootSlots
        self.rootSelected = rootSelected
        rootContinuousSelection = rootSelected
        self.arc = arc
        self.breadcrumb = breadcrumb
    }

    func update<Payload>(from navigation: RadialMenuNavigation<Payload>) {
        let root = navigation.root
        rootSlots = root.slots.map(GlassDialSlot.init)
        rootSelected = root.selection.selected
        rootContinuousSelection = root.selection.continuousSelection
        breadcrumb = navigation.breadcrumb

        guard navigation.depth > 0, let group = navigation.current.group else {
            arc = nil
            return
        }
        let frame = navigation.current
        let anchor = RadialMenuGeometry.rootSectors(count: root.slots.count)[root.selection.selected].center
        guard let window = RadialMenuGeometry.visibleWindow(slotCount: frame.slots.count,
                                                            selected: frame.selection.selected,
                                                            maxVisible: Self.maxVisibleArcSlots) else {
            arc = nil
            return
        }
        arc = GlassDialArc(id: group.id, anchor: anchor,
                           slots: frame.slots[window].map(GlassDialSlot.init),
                           selected: frame.selection.selected - window.lowerBound,
                           hasMoreBefore: window.lowerBound > 0,
                           hasMoreAfter: window.upperBound < frame.slots.count)
    }

    var selectedSlot: GlassDialSlot? {
        if let arc { return arc.slots.indices.contains(arc.selected) ? arc.slots[arc.selected] : nil }
        return rootSlots.indices.contains(rootSelected) ? rootSlots[rootSelected] : nil
    }
}

// MARK: - Views

struct GlassDialView: View {
    @ObservedObject var model: GlassDialModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let diameter: CGFloat = 228
    static let rootItemSize: CGFloat = 40
    static let rootIconRadius: CGFloat = diameter / 2 - rootItemSize / 2 - 12
    static let centerRadius: CGFloat = rootIconRadius - rootItemSize / 2 - 4
    static let arcInnerRadius: CGFloat = diameter / 2
    static let arcOuterRadius: CGFloat = arcInnerRadius + 54
    static let arcSlotSpan: Double = 30
    /// Room for the outer arc on every side, so the panel never clips it.
    static let footprint = CGSize(width: 2 * (arcOuterRadius + 18), height: 2 * (arcOuterRadius + 18))

    var body: some View {
        ZStack {
            DialGlass(shape: DialOutline(arc: model.arc))
            RootDialView(model: model, isSubdued: model.arc != nil)
            CenterWell()
            if let arc = model.arc {
                ArcView(arc: arc)
                    .id(arc.id)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            } else {
                CenterLabel(model: model).frame(width: 100)
            }
        }
        .frame(width: Self.footprint.width, height: Self.footprint.height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: model.rootContinuousSelection)
        .animation(reduceMotion ? .linear(duration: 0.1) : .smooth(duration: 0.24), value: model.arc)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        (model.breadcrumb + [model.selectedSlot?.title ?? ""]).filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// The circular glass dial with one wedge per root item.
private struct RootDialView: View {
    @ObservedObject var model: GlassDialModel
    let isSubdued: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    private let itemSize = GlassDialView.rootItemSize
    private var radius: CGFloat { GlassDialView.diameter / 2 }
    private var iconRadius: CGFloat { GlassDialView.rootIconRadius }
    private var innerRadius: CGFloat { GlassDialView.centerRadius }

    var body: some View {
        let sectors = RadialMenuGeometry.rootSectors(count: model.rootSlots.count)
        let span = sectors.first?.span ?? 360
        let inset = span < 360 ? min(1.5, span / 4) : 0
        let dividerColor = Color.primary.opacity(contrast == .increased ? 0.55 : 0.14)

        ZStack {
            Circle().stroke(dividerColor, lineWidth: 0.5)
            if !sectors.isEmpty {
                ZStack {
                    AnnularSector(startDegrees: -span / 2, endDegrees: span / 2,
                                  innerRadius: innerRadius, outerRadius: radius - 2)
                        .fill(Color.primary.opacity(0.1))
                    SelectionArc(startDegrees: -span / 2 + inset, endDegrees: span / 2 - inset,
                                 radius: radius - 2.5)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                .rotationEffect(.degrees(span * Double(model.rootContinuousSelection)))
            }

            RadialDividers(angles: sectors.count > 1 ? sectors.map(\.start) : [],
                           innerRadius: innerRadius, outerRadius: radius - 2)
                .stroke(dividerColor, lineWidth: 0.5)

            ForEach(Array(zip(model.rootSlots, sectors)), id: \.0.id) { slot, sector in
                let isSelected = slot.id == model.rootSlots[safe: model.rootSelected]?.id
                SlotIcon(slot: slot, isSelected: isSelected, size: itemSize)
                    .offset(polarOffset(degrees: sector.center, radius: iconRadius))
            }
        }
        .frame(width: GlassDialView.diameter, height: GlassDialView.diameter)
        .opacity(isSubdued ? 0.6 : 1)
    }
}

/// The outer arc that shows the active submenu around the parent's selection.
private struct ArcView: View {
    let arc: GlassDialArc
    @Environment(\.colorSchemeContrast) private var contrast

    private let inner = GlassDialView.arcInnerRadius, outer = GlassDialView.arcOuterRadius
    private let itemSize: CGFloat = 34

    var body: some View {
        let sectors = RadialMenuGeometry.arcSectors(anchor: arc.anchor, count: arc.slots.count,
                                                    slotSpan: GlassDialView.arcSlotSpan)
        let iconRadius = (inner + outer) / 2

        ZStack {
            if let first = sectors.first, let last = sectors.last {
                ZStack {
                    if let selected = sectors[safe: arc.selected] {
                        AnnularSector(startDegrees: selected.start + 1, endDegrees: selected.end - 1,
                                      innerRadius: inner + 3, outerRadius: outer - 3)
                            .fill(Color.primary.opacity(0.1))
                        SelectionArc(startDegrees: selected.start + 1.5, endDegrees: selected.end - 1.5,
                                     radius: outer - 2.5)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                    RadialDividers(angles: sectors.dropFirst().map(\.start),
                                   innerRadius: inner, outerRadius: outer)
                        .stroke(Color.primary.opacity(contrast == .increased ? 0.55 : 0.14), lineWidth: 0.5)
                    ForEach(Array(zip(arc.slots, sectors)), id: \.0.id) { slot, sector in
                        SlotIcon(slot: slot, isSelected: slot.id == arc.slots[safe: arc.selected]?.id,
                                 size: itemSize)
                            .offset(polarOffset(degrees: sector.center, radius: iconRadius))
                    }
                    if arc.hasMoreBefore { overflowDot(at: first.start - 4, radius: iconRadius) }
                    if arc.hasMoreAfter { overflowDot(at: last.end + 4, radius: iconRadius) }
                }
                .frame(width: GlassDialView.footprint.width, height: GlassDialView.footprint.height)
            }
            CenterLabel(arc: arc).frame(width: 100)
        }
    }

    private func overflowDot(at degrees: Double, radius: CGFloat) -> some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.8))
            .rotationEffect(.degrees(degrees))
            .offset(polarOffset(degrees: degrees, radius: radius))
    }
}

private struct SlotIcon: View {
    let slot: GlassDialSlot
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: slot.symbol)
            .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(Color.primary.opacity(isSelected ? 1 : 0.82))
            .shadow(color: Color(nsColor: .windowBackgroundColor).opacity(0.7), radius: 2)
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if slot.kind == .group {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.8))
                        .offset(x: -3, y: -5)
                }
            }
    }
}

private struct CenterWell: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Circle()
            .fill(Color(nsColor: .windowBackgroundColor).opacity(contrast == .increased ? 0.4 : 0.18))
            .overlay(Circle().stroke(Color.primary.opacity(contrast == .increased ? 0.55 : 0.14), lineWidth: 0.5))
            .frame(width: GlassDialView.centerRadius * 2, height: GlassDialView.centerRadius * 2)
    }
}

/// Title of the highlighted item, with the submenu path and a hint for what a click does.
private struct CenterLabel: View {
    private let title: String
    private let detail: String

    init(model: GlassDialModel) {
        let slot = model.selectedSlot
        title = slot?.title ?? ""
        detail = slot?.kind == .group ? "Click to open" : "Click to choose"
    }

    init(arc: GlassDialArc) {
        let slot = arc.slots[safe: arc.selected]
        title = slot?.title ?? ""
        switch slot?.kind {
        case .back: detail = "Click to go back"
        case .group: detail = "Click to open"
        default: detail = "Click to choose"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .contentTransition(.interpolate)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(0.8))
        }
    }
}

// MARK: - Glass and accessibility

private struct DialGlass<S: SwiftUI.Shape>: View {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                // Attenuate only the material, not the labels or icons above it.
                Color.clear
                    .glassEffect(.clear, in: shape)
                    .opacity(contrast == .increased ? 0.65 : 0.35)
            }
            shape.stroke(Color.primary.opacity(contrast == .increased ? 0.6 : 0.14),
                         lineWidth: contrast == .increased ? 1 : 0.5)
        }
    }
}

private func polarOffset(degrees: Double, radius: CGFloat) -> CGSize {
    let radians = degrees * .pi / 180
    return CGSize(width: sin(radians) * radius, height: -cos(radians) * radius)
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Previews

#if DEBUG
private enum GlassDialFixtures {
    static let root = [
        GlassDialSlot(id: "scroll", title: "Scroll", symbol: "scroll", kind: .leaf),
        GlassDialSlot(id: "media", title: "Media", symbol: "play.circle", kind: .group),
        GlassDialSlot(id: "zoom", title: "Zoom", symbol: "plus.magnifyingglass", kind: .leaf),
        GlassDialSlot(id: "brightness", title: "Brightness", symbol: "sun.max", kind: .leaf),
    ]

    static func arc(count: Int, selected: Int, titles: (Int) -> String = { "Item \($0)" }) -> GlassDialArc {
        let slots = [GlassDialSlot.back] + (1..<count).map {
            GlassDialSlot(id: "child-\($0)", title: titles($0), symbol: "circle.grid.2x2", kind: .leaf)
        }
        let window = RadialMenuGeometry.visibleWindow(slotCount: slots.count, selected: selected,
                                                      maxVisible: GlassDialModel.maxVisibleArcSlots) ?? 0..<1
        return GlassDialArc(id: "media", anchor: 90, slots: Array(slots[window]),
                            selected: selected - window.lowerBound,
                            hasMoreBefore: window.lowerBound > 0, hasMoreAfter: window.upperBound < slots.count)
    }
}

#Preview("Root") {
    GlassDialView(model: GlassDialModel(rootSlots: GlassDialFixtures.root, rootSelected: 1))
        .padding()
}

#Preview("Nested arc") {
    GlassDialView(model: GlassDialModel(rootSlots: GlassDialFixtures.root, rootSelected: 1,
                                        arc: GlassDialFixtures.arc(count: 4, selected: 1), breadcrumb: ["Media"]))
        .padding()
}

#Preview("Overflow") {
    GlassDialView(model: GlassDialModel(rootSlots: GlassDialFixtures.root, rootSelected: 1,
                                        arc: GlassDialFixtures.arc(count: 12, selected: 6), breadcrumb: ["Media"]))
        .padding()
}

#Preview("Long title") {
    GlassDialView(model: GlassDialModel(
        rootSlots: GlassDialFixtures.root, rootSelected: 1,
        arc: GlassDialFixtures.arc(count: 3, selected: 2) { _ in "An unusually long submenu item title" },
        breadcrumb: ["Media"]))
        .padding()
}
#endif
