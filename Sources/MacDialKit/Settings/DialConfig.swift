import Foundation

// MARK: - Keyboard shortcut

public struct KeyShortcut: Codable, Equatable, Hashable {
    public var keyCode: UInt16
    /// Device independent NSEvent.ModifierFlags raw value.
    public var modifiers: UInt
    public var keyName: String

    public init(keyCode: UInt16, modifiers: UInt, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers, keyName }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func number<T: Decodable>(_ type: T.Type, forKey key: CodingKeys) throws -> T {
            do {
                return try container.decode(type, forKey: key)
            } catch let error as DecodingError {
                guard case .dataCorrupted(let context) = error, context.codingPath.isEmpty else { throw error }
                throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath + [key],
                                                        debugDescription: "The value cannot be represented as \(type).",
                                                        underlyingError: context.underlyingError))
            } catch {
                throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath + [key],
                                                        debugDescription: "The value cannot be represented as \(type).",
                                                        underlyingError: error))
            }
        }
        keyCode = try number(UInt16.self, forKey: .keyCode)
        modifiers = try number(UInt.self, forKey: .modifiers)
        keyName = try container.decode(String.self, forKey: .keyName)
    }
}

// MARK: - Actions

public enum RotationAction: String, Codable, CaseIterable, Identifiable {
    case none
    case scrollVertical
    case scrollHorizontal
    case volume
    case brightness
    case switchDesktops
    case zoom
    case undoRedo
    case switchTabs
    case switchApps
    case mediaTracks
    case arrowsHorizontal
    case arrowsVertical
    case customShortcut

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "Nothing"
        case .scrollVertical: return "Scroll up / down"
        case .scrollHorizontal: return "Scroll left / right"
        case .volume: return "System volume"
        case .brightness: return "Display brightness"
        case .switchDesktops: return "Switch desktops (Spaces)"
        case .zoom: return "Zoom in / out"
        case .undoRedo: return "Undo / redo"
        case .switchTabs: return "Switch tabs"
        case .switchApps: return "Switch apps (⌘⇥)"
        case .mediaTracks: return "Previous / next track"
        case .arrowsHorizontal: return "Arrow keys ← →"
        case .arrowsVertical: return "Arrow keys ↑ ↓"
        case .customShortcut: return "Custom shortcuts…"
        }
    }

    /// Discrete actions fire once per N detents; continuous ones every detent.
    public var isContinuous: Bool {
        switch self {
        case .scrollVertical, .scrollHorizontal, .volume, .brightness: return true
        default: return false
        }
    }

    public var defaultStepsPerAction: Int {
        switch self {
        case .switchDesktops, .switchApps: return 4
        case .switchTabs, .mediaTracks: return 3
        case .zoom, .undoRedo: return 2
        default: return 1
        }
    }
}

public enum ClickAction: String, Codable, CaseIterable, Identifiable {
    case none
    case leftClick
    case rightClick
    case middleClick
    case doubleLeftClick
    case playPause
    case mute
    case nextTrack
    case previousTrack
    case missionControl
    case showDesktop
    case appExpose
    case radialMenu
    case nextMode
    case customShortcut
    case openApp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "Nothing"
        case .leftClick: return "Left click"
        case .rightClick: return "Right click"
        case .middleClick: return "Middle click"
        case .doubleLeftClick: return "Double click"
        case .playPause: return "Play / pause"
        case .mute: return "Mute"
        case .nextTrack: return "Next track"
        case .previousTrack: return "Previous track"
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Show desktop"
        case .appExpose: return "App windows"
        case .radialMenu: return "Open dial menu"
        case .nextMode: return "Next mode"
        case .customShortcut: return "Keyboard shortcut…"
        case .openApp: return "Open app…"
        }
    }

    public var isMouseButton: Bool {
        switch self {
        case .leftClick, .rightClick, .middleClick: return true
        default: return false
        }
    }
}

public struct RotationBinding: Codable, Equatable {
    /// Step-size range offered by the volume and brightness editor.
    public static let auxiliarySpeedRange = 1.0...4.0

    public var action: RotationAction = .none
    public var stepsPerAction: Int = 1
    public var reversed: Bool = false
    /// Multiplier for continuous actions (scroll distance, volume step size).
    public var speed: Double = 1.0
    public var clockwise: KeyShortcut?
    public var counterClockwise: KeyShortcut?

    public init(_ action: RotationAction = .none, steps: Int? = nil, reversed: Bool = false, speed: Double = 1.0,
         clockwise: KeyShortcut? = nil, counterClockwise: KeyShortcut? = nil) {
        self.action = action
        self.stepsPerAction = steps ?? action.defaultStepsPerAction
        self.reversed = reversed
        self.speed = speed
        self.clockwise = clockwise
        self.counterClockwise = counterClockwise
    }
}

public struct ClickBinding: Codable, Equatable {
    public var action: ClickAction = .none
    public var shortcut: KeyShortcut?
    public var appPath: String?

    public init(_ action: ClickAction = .none, shortcut: KeyShortcut? = nil, appPath: String? = nil) {
        self.action = action
        self.shortcut = shortcut
        self.appPath = appPath
    }
}

// MARK: - Mode (a "tool" in Surface Dial terms)

public struct DialMode: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var icon: String
    public var enabled = true
    public var rotate = RotationBinding()
    public var pressedRotate = RotationBinding()
    public var click = ClickBinding()
    public var doubleClick = ClickBinding()
    public var longPress = ClickBinding(.radialMenu)

    public init(id: UUID = UUID(), name: String, icon: String, enabled: Bool = true,
                rotate: RotationBinding = RotationBinding(), pressedRotate: RotationBinding = RotationBinding(),
                click: ClickBinding = ClickBinding(), doubleClick: ClickBinding = ClickBinding(),
                longPress: ClickBinding = ClickBinding(.radialMenu)) {
        self.id = id
        self.name = name
        self.icon = icon
        self.enabled = enabled
        self.rotate = rotate
        self.pressedRotate = pressedRotate
        self.click = click
        self.doubleClick = doubleClick
        self.longPress = longPress
    }

    public static let iconChoices = [
        "scroll", "speaker.wave.2.fill", "sun.max.fill", "rectangle.split.3x1", "plus.magnifyingglass",
        "arrow.uturn.backward", "music.note", "square.on.square", "keyboard", "arrow.left.arrow.right",
        "dial.medium.fill", "paintbrush.pointed.fill", "timeline.selection", "film", "photo",
        "pencil.tip", "textformat.size", "slider.horizontal.3", "gamecontroller.fill", "star.fill",
    ]

    public static var defaults: [DialMode] {
        [
            DialMode(name: "Scroll", icon: "scroll",
                     rotate: RotationBinding(.scrollVertical),
                     pressedRotate: RotationBinding(.scrollHorizontal),
                     click: ClickBinding(.leftClick),
                     doubleClick: ClickBinding(.none)),
            DialMode(name: "Volume", icon: "speaker.wave.2.fill",
                     rotate: RotationBinding(.volume),
                     pressedRotate: RotationBinding(.mediaTracks),
                     click: ClickBinding(.playPause),
                     doubleClick: ClickBinding(.nextTrack)),
            DialMode(name: "Desktops", icon: "rectangle.split.3x1",
                     rotate: RotationBinding(.switchDesktops),
                     pressedRotate: RotationBinding(.switchApps),
                     click: ClickBinding(.missionControl),
                     doubleClick: ClickBinding(.showDesktop)),
            DialMode(name: "Zoom", icon: "plus.magnifyingglass",
                     rotate: RotationBinding(.zoom),
                     click: ClickBinding(.customShortcut,
                                         shortcut: KeyShortcut(keyCode: 0x1D, modifiers: 1 << 20, keyName: "0"))),
            DialMode(name: "Undo", icon: "arrow.uturn.backward",
                     rotate: RotationBinding(.undoRedo)),
            DialMode(name: "Brightness", icon: "sun.max.fill", enabled: false,
                     rotate: RotationBinding(.brightness)),
        ]
    }
}

// MARK: - Config

public struct DialConfig: Codable, Equatable {
    /// Above ~120 the dial's haptic motor can't tick any finer.
    public static let ticksPerTurnRange = 4...120
    public static let defaultDoubleClickInterval = 0.3
    public static let defaultLongPressDuration = 0.5

    public var modes: [DialMode] = DialMode.defaults
    public var currentModeID: UUID?
    public var stepsPerRevolution: Int = 36
    public var detentHaptics = true
    public var menuHaptics = true
    public var showHUD = true
    public var radialAtCursor = true
    public var menuBarGlyph: MenuBarGlyph = .twoTone
    public var doubleClickInterval: Double = defaultDoubleClickInterval
    public var longPressDuration: Double = defaultLongPressDuration
    /// Reconnect to the dial as soon as it wakes from sleep (see BluetoothWaker).
    public var fastWake = true

    public var currentMode: DialMode {
        modes.first(where: { $0.id == currentModeID }) ?? modes.first ?? DialMode.defaults[0]
    }

    public var enabledModes: [DialMode] { modes.filter(\.enabled) }

    public mutating func selectMode(_ id: UUID) {
        currentModeID = id
    }

    /// Cycles through enabled modes, starting at the first if the current mode is disabled.
    public mutating func selectNextMode() {
        let enabled = enabledModes
        guard !enabled.isEmpty else { return }
        let index = enabled.firstIndex(where: { $0.id == currentMode.id }) ?? -1
        currentModeID = enabled[(index + 1) % enabled.count].id
    }

    // Tolerate missing keys so older/newer saved configs still load.
    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DialConfig()
        modes = (try? c.decode([DialMode].self, forKey: .modes)) ?? d.modes
        currentModeID = try? c.decode(UUID.self, forKey: .currentModeID)
        stepsPerRevolution = min(max((try? c.decode(Int.self, forKey: .stepsPerRevolution)) ?? d.stepsPerRevolution,
                                     Self.ticksPerTurnRange.lowerBound), Self.ticksPerTurnRange.upperBound)
        detentHaptics = (try? c.decode(Bool.self, forKey: .detentHaptics)) ?? d.detentHaptics
        menuHaptics = (try? c.decode(Bool.self, forKey: .menuHaptics)) ?? d.menuHaptics
        showHUD = (try? c.decode(Bool.self, forKey: .showHUD)) ?? d.showHUD
        radialAtCursor = (try? c.decode(Bool.self, forKey: .radialAtCursor)) ?? d.radialAtCursor
        menuBarGlyph = (try? c.decode(MenuBarGlyph.self, forKey: .menuBarGlyph)) ?? d.menuBarGlyph
        doubleClickInterval = (try? c.decode(Double.self, forKey: .doubleClickInterval)) ?? d.doubleClickInterval
        longPressDuration = (try? c.decode(Double.self, forKey: .longPressDuration)) ?? d.longPressDuration
        fastWake = (try? c.decode(Bool.self, forKey: .fastWake)) ?? d.fastWake
    }
}

public enum MenuBarGlyph: String, Codable, CaseIterable, Identifiable {
    case twoTone, outline, solid, color, modeIcon

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .twoTone: return "Dial"
        case .outline: return "Outline"
        case .solid: return "Solid"
        case .color: return "Color"
        case .modeIcon: return "Mode icon"
        }
    }
}
