/// One entry in a radial menu tree. A leaf carries a payload; a group opens
/// a submenu arc of its children.
public struct RadialMenuItem<Payload> {
    public enum Content {
        case leaf(Payload)
        case group([RadialMenuItem<Payload>])
    }

    public let id: String
    public let title: String
    public let symbol: String
    public let content: Content

    public init(id: String, title: String, symbol: String, content: Content) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.content = content
    }

    public static func leaf(id: String, title: String, symbol: String, payload: Payload) -> Self {
        Self(id: id, title: title, symbol: symbol, content: .leaf(payload))
    }

    public static func group(id: String, title: String, symbol: String,
                             children: [RadialMenuItem<Payload>]) -> Self {
        Self(id: id, title: title, symbol: symbol, content: .group(children))
    }

    public var isGroup: Bool {
        if case .group = content { return true }
        return false
    }
}

/// A selectable position on the root dial or a submenu arc.
public enum RadialMenuSlot<Payload> {
    /// Returns to the parent level. Present only on submenu arcs, always first.
    case back
    case item(RadialMenuItem<Payload>)

    public var item: RadialMenuItem<Payload>? {
        if case .item(let item) = self { return item }
        return nil
    }
}

/// One visible level: the root dial or the submenu arc of an opened group.
public struct RadialMenuFrame<Payload> {
    /// The group that opened this level, or nil for the root dial.
    public let group: RadialMenuItem<Payload>?
    public let slots: [RadialMenuSlot<Payload>]
    public internal(set) var selection: RadialMenuSelection

    public var selectedSlot: RadialMenuSlot<Payload> { slots[selection.selected] }
}

public enum RadialMenuValidationError: Error, Equatable {
    case emptyMenu
    case emptyGroup(id: String)
    case duplicateID(String)
    case invalidDetentsPerItem(Int)
}

public enum RadialMenuConfirmation<Payload> {
    /// A submenu arc opened; the menu must stay visible.
    case enteredGroup(RadialMenuItem<Payload>)
    /// The current arc closed and the parent level is active again.
    case returned
    /// A leaf was chosen; the caller should dismiss the menu and act once.
    case selectedLeaf(RadialMenuItem<Payload>)
}

/// Dial-driven navigation through a radial menu tree, independent of presentation.
///
/// The root dial stays on the stack while one submenu arc is active at a time.
/// Entering a group selects its first child, Back restores the parent's
/// selection, and every level change discards partial detent movement.
public struct RadialMenuNavigation<Payload> {
    public private(set) var frames: [RadialMenuFrame<Payload>]
    private let detentsPerItem: Int

    public init(items: [RadialMenuItem<Payload>], selectedID: String?, detentsPerItem: Int) throws {
        guard detentsPerItem > 0 else { throw RadialMenuValidationError.invalidDetentsPerItem(detentsPerItem) }
        guard !items.isEmpty else { throw RadialMenuValidationError.emptyMenu }
        var seen = Set<String>()
        try Self.validate(items, seen: &seen)

        let selected = selectedID.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? 0
        let selection = RadialMenuSelection(itemCount: items.count, selected: selected,
                                            detentsPerItem: detentsPerItem)!
        self.detentsPerItem = detentsPerItem
        frames = [RadialMenuFrame(group: nil, slots: items.map { .item($0) }, selection: selection)]
    }

    public var root: RadialMenuFrame<Payload> { frames[0] }
    public var current: RadialMenuFrame<Payload> { frames[frames.count - 1] }
    /// Zero at the root dial, one for the first submenu arc, and so on.
    public var depth: Int { frames.count - 1 }
    /// Titles of the opened groups, outermost first.
    public var breadcrumb: [String] { frames.compactMap { $0.group?.title } }

    /// Returns true when the selected slot of the active level changed.
    @discardableResult
    public mutating func move(by delta: Int) -> Bool {
        frames[frames.count - 1].selection.move(by: delta)
    }

    public mutating func confirm() -> RadialMenuConfirmation<Payload> {
        switch current.selectedSlot {
        case .back:
            frames.removeLast()
            frames[frames.count - 1].selection.discardPartialMovement()
            return .returned
        case .item(let item):
            switch item.content {
            case .leaf:
                return .selectedLeaf(item)
            case .group(let children):
                frames[frames.count - 1].selection.discardPartialMovement()
                let slots: [RadialMenuSlot<Payload>] = [.back] + children.map { .item($0) }
                // Validation guarantees at least one child, so slot 1 exists.
                let selection = RadialMenuSelection(itemCount: slots.count, selected: 1,
                                                    detentsPerItem: detentsPerItem)!
                frames.append(RadialMenuFrame(group: item, slots: slots, selection: selection))
                return .enteredGroup(item)
            }
        }
    }

    private static func validate(_ items: [RadialMenuItem<Payload>], seen: inout Set<String>) throws {
        for item in items {
            guard seen.insert(item.id).inserted else { throw RadialMenuValidationError.duplicateID(item.id) }
            if case .group(let children) = item.content {
                guard !children.isEmpty else { throw RadialMenuValidationError.emptyGroup(id: item.id) }
                try validate(children, seen: &seen)
            }
        }
    }
}
