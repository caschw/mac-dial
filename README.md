# Mac Dial

Native Microsoft Surface Dial support for macOS, with SwiftUI settings and a press-and-hold radial menu.

Mac Dial reads the dial through Apple's IOKit rather than relying on macOS's mouse-event interpretation. Configure rotation, pressed rotation, click, double-click, and hold gestures for scrolling, volume, keyboard shortcuts, media controls, and other actions.

## Requirements and installation

- macOS 14 Sonoma or later; Apple Silicon is the primary development platform.
- A paired Microsoft Surface Dial for hardware input.
- Full Xcode with a macOS SDK to build the app; Command Line Tools alone are not sufficient.
- Accessibility permission for generated input; Bluetooth permission for instant wake, and Input Monitoring if requested by macOS.

This branch establishes the Xcode application baseline at **version 1.0, build 1**. It does not publish a new release or provide a notarized download. [Build from source](docs/building.md), copy the resulting **Mac Dial.app** to Applications, and follow the [setup and usage guide](docs/usage.md).

## Documentation

| Guide | Contents |
|---|---|
| [Building and local installation](docs/building.md) | Xcode, command-line builds, signing, permissions, and verification |
| [Using Mac Dial](docs/usage.md) | Pairing, modes, gestures, supported actions, and settings |
| [Architecture](docs/architecture.md) | Source boundaries, input flow, persistence, and future migration |
| [Contributing](docs/contributing.md) | Swift conventions, scope, attribution, and validation |
| [Security policy](SECURITY.md) | Private vulnerability reporting and permission use |
| [Agent guidance](AGENTS.md) | Repository direction and constraints for coding agents |

## Repository layout

```text
MacDial.xcodeproj/     macOS app target and shared MacDial scheme
Sources/MacDial/
  App/                Entry point and application lifecycle
  Device/             IOKit HID access and Bluetooth wake support
  Input/              Gesture interpretation and orchestration
  Actions/            System, keyboard, mouse, and media actions
  Settings/           Configuration, persistence, and SwiftUI settings
  UI/                 Menu bar, radial menu, HUD, and dial glyph
Resources/            Info.plist and app icon asset catalog
docs/                 Build, usage, architecture, and contribution guides
```

## Lineage and direction

This project builds on [andreasjhkarlsson/mac-dial](https://github.com/andreasjhkarlsson/mac-dial) and the native Apple Silicon foundation from [camerondehart/mac-dial-AppleSilicon](https://github.com/camerondehart/mac-dial-AppleSilicon). Thanks to Andreas Karlsson for the original app and HID protocol work, and to [daniel5151/surface-dial-linux](https://github.com/daniel5151/surface-dial-linux) for haptics protocol reference.

[diversifiedfun/mac-dial](https://github.com/diversifiedfun/mac-dial) is a future visual and feature reference, especially for a more modern dial menu. This restructuring does not port its features or redesign the existing menu. Future work should retain a primarily SwiftUI application and native IOKit dial support; see the [architecture direction](docs/architecture.md#future-migration).

## License

[MIT](LICENSE). Original copyright 2021 Andreas Karlsson; copyright 2026 Carl Schweitzer. Preserve upstream notices and attribute any future third-party ports.
