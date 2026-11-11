# Architecture

Mac Dial has a macOS application, a MacDialKit framework, and hostless unit tests,
with no third-party runtime dependencies.
SwiftUI supplies settings and overlay content; AppKit hosts windows, the menu bar,
and application lifecycle. IOKit reads Surface Dial HID reports directly and sends
haptic output. CoreBluetooth keeps the paired dial ready for instant wake.

## Source boundaries

| Folder under `Sources/MacDial` | Responsibility |
|---|---|
| `App` | `main.swift` starts NSApplication; `AppDelegate` composes services, handles permissions, launch at login, settings windows, and teardown |
| `Device` | `DialDevice` owns HID discovery, reports, connection state, and haptics; `BluetoothWaker` manages wake reconnection |
| `Input` | `DialController` forwards reports to MacDialKit and coordinates settings, actions, and overlays; `MainRunLoopScheduler` supplies Foundation timers and wall-clock time |
| `Actions` | `Actions.swift` implements native system, keyboard, mouse, volume, brightness, and media operations |
| `Settings` | `SettingsStore` persists MacDialKit configuration and publishes changes; AppKit shortcut helpers and `SettingsView` provide presentation |
| `UI` | `StatusBarController` handles the menu bar; `Overlays` contains the radial menu and HUD; `DialGlyph` draws icons |

`Sources/MacDialKit` contains the platform-independent behavior:

| Folder | Responsibility |
|---|---|
| `Settings` | Codable configuration, stable action enums and bindings, current-mode fallback, and enabled-mode cycling |
| `Input` | `GestureInterpreter` maps button/rotation input to actions and menu operations; injectable scheduling and side-effect protocols |
| `Actions` | `RotationInterpreter` selects continuous scroll/volume/brightness effects and discrete action thresholds, reversal, and acceleration |

MacDialKit imports only Foundation. It does not instantiate hardware services,
system-event generators, UI controllers, or settings persistence. The app links
and embeds the framework; its sources are not also compiled into the app.

## Input and presentation flow

```text
Surface Dial -> DialDevice -> DialController -> GestureInterpreter (MacDialKit)
                                  |                   |
                                  |                   +-> DialActions -> ActionEngine
                                  |                   |                    |
                                  |                   |             RotationInterpreter (MacDialKit)
                                  |                   |                    |
                                  |                   |             native system events
                                  |                   +-> DialMenu -> radial menu
SettingsStore --------------------+-> HUD / settings / menu bar
BluetoothWaker ----------------------> paired-dial wake reconnection
```

HID callbacks are scheduled on the main run loop. Bluetooth delegates use the
main queue. Gesture scheduling, action state, and UI coordination retain that
ordering. `GestureScheduler` and its cancellation tokens must be used on the
same serial context as input. The app adapter uses `Timer.scheduledTimer` on the
main run loop, in its existing default mode, and `Date` for rotation timing.
Tests substitute a manually advanced clock; they do not sleep or require a dial.

`AppDelegate` creates shared settings, device, status, scheduler, action, wake,
and overlay collaborators and injects them into `DialController`. The controller
owns the gesture interpreter, forwards input, and applies device settings.
Mode changes cancel pending click/hold timers and retain the existing HUD and
haptic policy. Mouse-only bindings still pass down/up through for dragging.
GestureInterpreter cancels pending timers on destruction as well.
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
archiving. Its Test action runs `MacDialKitTests`, a hostless XCTest target that
links the framework rather than launching the app. Tests cover button/rotation
sequences, exact click/hold timing, cancellation, menu and haptic decisions,
mouse passthrough, rotation thresholds/acceleration, mode cycling, and legacy
settings decoding and encoding. The initial characterization tests were run
against the original source with temporary test-only platform doubles before
extraction; those duplicate source memberships were removed when tests switched
to importing MacDialKit.

`Resources/Info.plist` retains accessory-app and Bluetooth privacy metadata.
`Resources/Assets.xcassets/AppIcon.appiconset` contains the existing icon artwork
at standard macOS sizes. Xcode compiles it into the app; no custom build script
generates the icon. Add sources and resources to their owning target's build
phases exactly once and keep Info.plist out of Copy Bundle Resources.

## Future migration

The framework and tests implement the structural extraction described in
[MacDialKit and behavior tests (#1)](https://github.com/caschw/mac-dial/issues/1).
SwiftUI/AppKit presentation and concrete IOKit, CoreBluetooth, and system-action
implementations remain in the app. This is not a concurrency redesign, a new
settings schema, or a radial-menu redesign.

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
