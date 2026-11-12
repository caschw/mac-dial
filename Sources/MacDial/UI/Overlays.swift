import AppKit
import SwiftUI
import MacDialKit

/// Transparent, click-through panel that floats above everything (including
/// full screen apps) without stealing focus.
final class OverlayPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func fade(in visible: Bool, completion: (() -> Void)? = nil) {
        if visible {
            alphaValue = 0
            orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = visible ? 0.12 : 0.2
            animator().alphaValue = visible ? 1 : 0
        }, completionHandler: {
            // Skip if a fade-in interrupted this fade-out.
            if !visible && self.alphaValue < 0.01 { self.orderOut(nil) }
            completion?()
        })
    }

    static func screenUnderCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
    }
}

// MARK: - Radial menu

/// Shows the glass dial and drives nested submenus with `RadialMenuNavigation`.
final class RadialMenuController: DialMenu {
    /// Returning false keeps the selector open after an invalid/stale choice.
    var onSelect: ((DialMenuChoice) -> Bool)?
    private(set) var isVisible = false

    private let model = GlassDialModel()
    private lazy var panel: OverlayPanel = {
        let panel = OverlayPanel(size: GlassDialView.footprint)
        panel.contentView = NSHostingView(rootView: GlassDialView(model: model))
        return panel
    }()
    private var navigation: RadialMenuNavigation<DialMenuChoice>?
    private var idleTimer: Timer?
    private var preferredOutputUID: String?

    func show(modes: [DialMode], selectedID: UUID, detentsPerItem: Int, atCursor: Bool) {
        let items = modes.map {
            RadialMenuItem(id: $0.id.uuidString, title: $0.name, symbol: $0.icon, content: .leaf(DialMenuChoice.mode($0)))
        }
        show(items: items, selectedID: selectedID.uuidString, detentsPerItem: detentsPerItem, atCursor: atCursor)
    }

    func show(items: [RadialMenuItem<DialMenuChoice>], selectedID: String?, detentsPerItem: Int, atCursor: Bool,
              enterGroup: Bool = false, preferredOutputUID: String? = nil) {
        self.preferredOutputUID = preferredOutputUID
        do {
            navigation = try RadialMenuNavigation(items: items, selectedID: selectedID,
                                                  detentsPerItem: detentsPerItem)
            if enterGroup, navigation?.current.selectedSlot.item?.isGroup == true {
                _ = navigation?.confirm()
                selectPreferredOutput()
            }
        } catch {
            NSLog("MacDial: ignoring invalid radial menu configuration: %@", String(describing: error))
            return
        }
        refreshModel()

        let size = GlassDialView.footprint
        let visible = OverlayPanel.screenUnderCursor()?.visibleFrame ?? .zero
        let desired = atCursor ? NSEvent.mouseLocation : NSPoint(x: visible.midX, y: visible.midY)
        let center = RadialMenuGeometry.clampedCenter(desired, footprint: size, in: visible)
        panel.setFrameOrigin(NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))

        isVisible = true
        panel.fade(in: true)
        bumpIdleTimer()
    }

    /// Returns true when the highlighted item changed.
    @discardableResult
    func move(by delta: Int) -> Bool {
        guard isVisible else { return false }
        bumpIdleTimer()
        let changed = navigation?.move(by: delta) ?? false
        if changed { refreshModel() }
        return changed
    }

    /// Opens a highlighted group, returns from Back, or chooses a leaf and closes the menu.
    func confirm() {
        guard isVisible, let result = navigation?.confirm() else { return }
        switch result {
        case .enteredGroup:
            selectPreferredOutput()
            refreshModel()
            bumpIdleTimer()
        case .returned:
            refreshModel()
            bumpIdleTimer()
        case .selectedLeaf(let item):
            guard case .leaf(let choice) = item.content else { return }
            if onSelect?(choice) == true { dismiss() }
            else { bumpIdleTimer() }
        }
    }

    func replaceItems(_ items: [RadialMenuItem<DialMenuChoice>]) {
        guard isVisible else { return }
        do {
            try navigation?.replaceItems(items)
            refreshModel()
        } catch {
            NSLog("MacDial: unable to refresh audio menu: %@", error.localizedDescription)
            dismiss()
        }
    }

    private func selectPreferredOutput() {
        guard let navigation,
              let id = AudioOutputMenu.preferredItemID(in: navigation.current.slots.compactMap(\.item),
                                                       selectedUID: preferredOutputUID) else { return }
        self.navigation?.selectItem(id: id)
    }

    func dismiss() {
        guard isVisible else { return }
        isVisible = false
        navigation = nil
        idleTimer?.invalidate()
        panel.fade(in: false)
    }

    private func refreshModel() {
        guard let navigation else { return }
        model.update(from: navigation)
    }

    private func bumpIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
}

// MARK: - Mode HUD

final class HUDModel: ObservableObject {
    @Published var icon = "dial.medium.fill"
    @Published var title = ""
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: model.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(model.title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassBackground(in: Capsule())
        .padding(24)
        .fixedSize(horizontal: false, vertical: true)
    }
}

final class HUDController {
    private let model = HUDModel()
    private lazy var panel: OverlayPanel = {
        let panel = OverlayPanel(size: NSSize(width: 320, height: 100))
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }()
    private var hideTimer: Timer?

    func show(icon: String, title: String) {
        model.icon = icon
        model.title = title

        let availableWidth = OverlayPanel.screenUnderCursor()?.visibleFrame.width ?? 640
        let textWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium)]).width
        let size = NSSize(width: min(availableWidth, max(320, textWidth + 100)), height: 100)
        panel.setContentSize(size)
        if let screen = OverlayPanel.screenUnderCursor() {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 80))
        }

        hideTimer?.invalidate()
        if !panel.isVisible || panel.alphaValue < 1 { panel.fade(in: true) }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            self?.panel.fade(in: false)
        }
    }
}

// MARK: - Liquid Glass

extension View {
    /// Liquid Glass behind the content, so icons and text stay sharp.
    func glassBackground<S: SwiftUI.Shape>(in shape: S) -> some View {
        glassEffect(.regular, in: shape)
    }
}
