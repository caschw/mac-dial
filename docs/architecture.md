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
| `Actions` | `Actions.swift` implements native system, keyboard, mouse, volume, brightness, and media operations; `AudioOutputService` owns Core Audio discovery, listeners, and selected-device volume control |
| `Settings` | `SettingsStore` publishes configuration changes and provides recovery UI; AppKit shortcut helpers and `SettingsView` provide presentation |
| `UI` | `StatusBarController` handles the menu bar; `Overlays` contains the radial-menu controller, panels, and HUD; `GlassDialView` renders the glass dial and nested arcs; `DialGlyph` draws icons |

`Sources/MacDialKit` contains the platform-independent behavior:

| Folder | Responsibility |
|---|---|
| `Device` | Pure HID report validation and ordered button/rotation decoding |
| `Settings` | Codable configuration, stable action enums and bindings, mode selection, and protected settings persistence |
| `Input` | `GestureInterpreter` maps button/rotation input to actions and menu operations; injectable scheduling and side-effect protocols |
| `Actions` | `RotationInterpreter` selects effects; `RotationEffectQueue` delivers bounded, ordered batches; `AppSwitchCoordinator` sequences app-switch keys and timers; audio preferences, eligibility, scalar arithmetic, and menu payloads remain Foundation-only |
| `UI` | Radial-menu selection and detent accumulation, nested-menu navigation (`RadialMenuNavigation`), and dial/arc geometry (`RadialMenuGeometry`) |

MacDialKit imports only Foundation. It does not instantiate hardware services,
system-event generators, or UI controllers. The app links
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
A zero-delay scheduler may invoke an action before returning its cancellation
token; completed actions are not retained as pending gestures.

### Radial menu

The long-press action opens the menu through `DialController.showRadialMenu()`,
which calls `RadialMenuController.show`. After that, `GestureInterpreter` drives
it only through `DialMenu` (`isVisible`, `move`, `confirm`, `dismiss`).
`RadialMenuController` owns a
`RadialMenuNavigation` built from the enabled modes; confirming a group pushes a
frame whose first slot is **Back**, confirming **Back** pops it, and only a leaf
selection closes the menu only after its handler succeeds. Ordinary leaves
select a mode; output leaves update the volume target without changing the
operating mode. Informational or stale choices leave the menu open.
`GlassDialModel` projects the
navigation state into SwiftUI: the root dial, plus one outer arc anchored at the
selected root sector and windowed to seven slots by
`RadialMenuGeometry.visibleWindow`. The panel is positioned with
`RadialMenuGeometry.clampedCenter` so the full arc footprint stays on screen.
The root and active arc share one continuous glass contour, with the arc's
inner radius equal to the unscaled root radius. Only the glass background is
attenuated for transparency; icons and labels are separate foreground layers.
The outer contour, center well, and selected sectors share `GlassSurface`
styling as separate native glass surfaces, while the selection's accent rim
stays in the foreground. Root selection animates the sector and rim paths in a
fixed view rather than rotating the glass host, which can displace the native
material outside the dial. Reduce Transparency substitutes an opaque
background for the entire contour and omits the inset glass effects.
`DialController` dismisses an open menu when the enabled modes or steps per
revolution change. Volume Output is a utility group with live device choices in
the secondary arc. Its optional mode kind distinguishes it from ordinary modes;
there is still no user-configurable nested-menu schema. Live tree replacement
validates atomically, retains surviving group paths and selected stable IDs,
discards partial detents, and selects Back when an arc choice disappears.

`AudioOutputService` receives Core Audio notifications on the main queue and
coalesces discovery refreshes. It observes device/default-output changes,
device ownership/name/liveness/streams, and output-stream virtual formats.
Stable Core Audio UIDs identify choices; names are display labels only.
Settings retains disabled UID/name records even when disconnected, while new
supported devices are eligible unless disabled. The selected UID is independent
of menu hiding. Missing targets temporarily use the existing system-volume key
path; returning targets resume automatically. Connected targets with unavailable
controls report errors rather than redirecting volume elsewhere. System routing,
mute, and media actions are unchanged.

Core Audio property sizes, returned array sizes, identities, and overflowing
channel counts are checked before use. Volume writes require writable master
controls or all writable output channels and finite scalars in 0...1. Fine
steps use 1/64 of the scalar range, saturate large positive counts safely,
preserve channel balance, and attempt rollback on partial channel-write failure.
Direct writes do not trigger the native macOS volume HUD. Explicit utility entry
and successful output selection cancel pending click/hold timers; they do not
replace the working mode or announce a second mode transition.
Next Mode retains an in-memory utility cursor so a later cycle advances past
the utility rather than reopening it indefinitely. An ordinary mode selection
clears that cursor; no temporary mode ID is written to preferences.

`AppDelegate` creates shared settings, device, status, scheduler, action, wake,
and overlay collaborators and injects them into `DialController`. The controller
owns the gesture interpreter, forwards input, and applies device settings.
Mode changes cancel pending click/hold timers and retain the existing HUD and
haptic policy. Mouse-only bindings still pass down/up through for dragging.
GestureInterpreter cancels pending timers on destruction as well.
The app normally runs as an accessory/menu-bar utility; opening settings
temporarily gives it regular Dock and app-switcher presence. Closing settings
restores accessory behavior.

`DialDevice` owns the native callback and uses MacDialKit to validate callback
status and buffer length before reading a report, logging invalid reports. The
existing first-byte report ID and button-before-rotation ordering are unchanged.
HID reports contain signed 8-bit deltas; the gesture and rotation interpreters
also accept aggregate `Int` detent counts. Zero does nothing. Duplicate presses
are ignored so they cannot restart a hold or duplicate a mouse-down event.

Rotation selection rejects nonfinite timestamps, invalid continuous speeds, and
scroll distances that cannot be represented by the native signed 32-bit event.
A backwards clock is treated as a pause. Volume and brightness repeat counts
that exceed the representable `Int` range are logged and rejected. Rotation
effects are produced lazily and delivered in batches of at most 512 effects or
press/release pairs per main-queue turn. The queue accepts at most 4,096 pending
rotation events; a burst that would exceed this budget is rejected and logged
rather than leaving controls behind an unbounded backlog. Rejected rotations do
not change the interpreter's remainder or timing. Accepted rotations, clicks,
mouse events, and app-switch-completion events remain in order; timers from
older queued app switches cannot finish a newer switch, and the release delay
starts after the last event in a switch request. Menu and mode changes still
update gesture state immediately. Queue cancellation, including shutdown, cancels
switch timers and releases any mouse button or app-switch modifier already
pressed. Work enqueued by release callbacks waits until cancellation finishes.
Each output queue accepts one app-switch coordinator, which balances Command
when destroyed. A committed switch keeps its coordinator alive until its ordered
release or cancellation, so queued Tabs are not lost when the owner goes away.
Separate queues must not control the same keyboard stream. The queue's scheduler
must enqueue asynchronously on the same serial context as its callers.
Nonfinite or negative gesture durations use the existing default durations when
scheduling; zero and nonnegative values outside the editor ranges remain usable.
These checks do not rewrite stored settings.

## Persistence and compatibility

Configuration is JSON-encoded in `UserDefaults` at `dialConfig.v2`. The remembered
Bluetooth peripheral identifier uses `dialPeripheralIdentifier`. The bundle
identifier is `local.macdial.MacDial`, which identifies the app's standard
preferences domain. Marketing versions are independent of the settings schema;
changing the app version must not reset saved configuration.

The additive `audioOutput` preferences hold the selected UID and disabled
UID/name records. An optional `kind` marks utility modes; legacy absence denotes
ordinary modes. A `volumeOutputModeIntroduced` marker permits a one-time,
idempotent addition of Volume Output to existing installations. The migration
preserves custom modes, bindings, selection, and all other settings, explicitly
saves only when storage is writable, and respects later utility deletion.
Malformed preferences, duplicate/empty identities, and unknown fields or kinds
remain subject to the protected-storage policy below.

Preserve Codable keys, enum raw values, default/fallback decoding, and exported
settings compatibility. Any future schema change needs migration design and
focused regression tests with older configurations. If a stored document is
malformed or contains fields or values this version cannot understand, the
existing decoding fallbacks still apply, but the original is protected from
automatic writes. Settings opens with a warning; edits remain temporary until
the user explicitly confirms replacement. The original can be exported first.
Before saving or replacing, the store checks whether the saved value changed
since it was last observed. If so, it protects the newer value and requires a
fresh confirmation. This is an optimistic check: UserDefaults does not provide
an atomic cross-process compare-and-set, so simultaneous writers can still race.

## Build and resources

`MacDial.xcodeproj` is the authoritative build definition. Its shared `MacDial`
scheme builds Debug and Release and supports running, profiling, analysis, and
archiving. Its Test action runs `MacDialKitTests`, a hostless XCTest target that
links the framework rather than launching the app. Tests cover button/rotation
sequences, exact click/hold timing, cancellation, menu and haptic decisions,
mouse passthrough, rotation thresholds/acceleration, mode cycling, and legacy
settings decoding and encoding, as well as invalid numeric inputs, signed HID
bytes and aggregate deltas, malformed configuration fallbacks, and pure HID
report decoding. They do not execute the native HID callback or other native
integrations. The initial characterization tests were run against the original
source with temporary test-only platform doubles before extraction; those
duplicate source memberships were removed when tests switched to importing
MacDialKit.

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
settings schema.

The glass radial menu with nested arcs
([#4](https://github.com/caschw/mac-dial/issues/4)) took visual inspiration
from [diversifiedfun/mac-dial](https://github.com/diversifiedfun/mac-dial) at
revision `3bb6d4baac2f17a37bdf74845560f458bcdb58cc`. It is an original SwiftUI
implementation; no code or assets were copied. Continue to use that project as
a visual and feature reference.
Evaluate individual ports against the native Apple Silicon input foundation from
[camerondehart/mac-dial-AppleSilicon](https://github.com/camerondehart/mac-dial-AppleSilicon)
and the original
[andreasjhkarlsson/mac-dial](https://github.com/andreasjhkarlsson/mac-dial).

The desired direction is a more modern, primarily SwiftUI interface with native
IOKit dial support, not replacement of the input stack. Menu changes should keep
presentation separate from gesture interpretation, preserve configurable
actions and haptic behavior, and consider accessibility, light/dark appearance,
and keyboard interaction on the macOS 26.0 minimum. Other feature ports, and
configurable nested menus in settings, are planned work rather than implemented
functionality.

Before copying code or assets, inspect the source revision and license, retain
required notices, and document provenance. Existing MIT terms and original
copyright notices must remain intact.
