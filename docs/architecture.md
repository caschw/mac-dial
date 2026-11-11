# Architecture

Mac Dial is one macOS application target with no third-party runtime dependencies.
SwiftUI supplies settings and overlay content; AppKit hosts windows, the menu bar,
and application lifecycle. IOKit reads Surface Dial HID reports directly and sends
haptic output. CoreBluetooth keeps the paired dial ready for instant wake.

## Source boundaries

| Folder under `Sources/MacDial` | Responsibility |
|---|---|
| `App` | `main.swift` starts NSApplication; `AppDelegate` composes services, handles permissions, launch at login, settings windows, and teardown |
| `Device` | `DialDevice` owns HID discovery, reports, connection state, and haptics; `BluetoothWaker` manages wake reconnection |
| `Input` | `DialController` maps reports to rotation, pressed rotation, click, double-click, and hold gestures; coordinates actions and overlays |
| `Actions` | `Actions.swift` implements native system, keyboard, mouse, volume, brightness, and media operations |
| `Settings` | `Settings.swift` defines Codable configuration and persistence; `SettingsView.swift` edits it with SwiftUI |
| `UI` | `StatusBarController` handles the menu bar; `Overlays` contains the radial menu and HUD; `DialGlyph` draws icons |

The folder boundaries clarify the existing design; they do not introduce new
modules, dependency-injection layers, or a behavior rewrite.

## Input and presentation flow

```text
Surface Dial -> DialDevice -> DialController -> configured action
                                  |
                                  +-> radial menu / HUD
SettingsStore --------------------+-> settings and menu-bar presentation
BluetoothWaker ----------------------> paired-dial wake reconnection
```

HID callbacks are scheduled on the main run loop. Bluetooth delegates use the
main queue. Gesture timers, action state, and UI coordination currently depend
on that ordering. Preserve it until an explicit concurrency redesign can verify
timing and ownership.

`AppDelegate` creates shared settings, device, and status objects. The controller
owns gesture coordination and its action, wake, and overlay collaborators.
The app normally runs as an accessory/menu-bar utility; opening settings
temporarily gives it regular Dock and app-switcher presence. Closing settings
restores accessory behavior.

## Persistence and compatibility

Configuration is JSON-encoded in `UserDefaults` at `dialConfig.v2`. The remembered
Bluetooth peripheral identifier uses `dialPeripheralIdentifier`. The bundle
identifier is `local.macdial.MacDial`, which identifies the app's standard
preferences domain. Marketing versions are independent of the settings schema;
changing the app version must not reset saved configuration.

Preserve Codable keys, enum raw values, default/fallback decoding, and exported
settings compatibility. Any future schema change needs migration design and
focused regression tests with older configurations.

## Build and resources

`MacDial.xcodeproj` is the authoritative build definition. Its shared `MacDial`
scheme builds Debug and Release and supports running, profiling, analysis, and
archiving. There is no test target yet.

`Resources/Info.plist` retains accessory-app and Bluetooth privacy metadata.
`Resources/Assets.xcassets/AppIcon.appiconset` contains the existing icon artwork
at standard macOS sizes. Xcode compiles it into the app; no custom build script
generates the icon. Add sources and resources to their owning target's build
phases exactly once and keep Info.plist out of Copy Bundle Resources.

## Future migration

Core extraction and testability are tracked in
[MacDialKit and behavior tests (#1)](https://github.com/caschw/mac-dial/issues/1).
That planned work adds behavior tests before extracting configuration, gesture
interpretation, and action-selection logic into an Xcode framework target.
SwiftUI/AppKit presentation and concrete IOKit, CoreBluetooth, and system-action
implementations remain in the app, composed at its boundary. MacDialKit is not
implemented yet; the existing folder boundaries do not constitute a framework.

Use [diversifiedfun/mac-dial](https://github.com/diversifiedfun/mac-dial) as a
future visual and feature reference, especially its dial-menu appearance.
Evaluate individual ports against the native Apple Silicon input foundation from
[camerondehart/mac-dial-AppleSilicon](https://github.com/camerondehart/mac-dial-AppleSilicon)
and the original
[andreasjhkarlsson/mac-dial](https://github.com/andreasjhkarlsson/mac-dial).

The desired direction is a more modern, primarily SwiftUI interface with native
IOKit dial support, not replacement of the input stack. A future menu redesign
should separate presentation from gesture interpretation, preserve configurable
actions and haptic behavior, and consider accessibility, light/dark appearance,
keyboard interaction, and macOS 14 fallbacks. Feature selection and acceptance
criteria belong in separate changes; the redesign and feature ports are planned
work rather than implemented functionality.

Before copying code or assets, inspect the source revision and license, retain
required notices, and document provenance. Existing MIT terms and original
copyright notices must remain intact.
