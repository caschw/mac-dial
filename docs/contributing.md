# Contributing

Read the [architecture](architecture.md), [build guide](building.md), and
[agent guidance](../AGENTS.md) before making changes. Use private reporting for
[security vulnerabilities](../SECURITY.md), not public issues.

## Changes and coding style

Keep changes focused, with sensible commits at architectural or documentation
boundaries. Describe user-visible behavior and compatibility effects in the
change description. UI redesigns and ports from other dial implementations
should be separately scoped, not hidden inside maintenance or folder moves.

Follow Apple's [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/):
clear names, consistent argument labels, small responsibilities, explicit access
control, and value types where appropriate. Follow the established four-space
Swift indentation and use SwiftUI for new presentation where practical. AppKit
and native frameworks remain appropriate for macOS integration. Avoid adding
dependencies or abstractions without a concrete need.

Maintain macOS 14 availability checks and main-thread UI updates. Do not
casually change gesture timers, event ordering, permission handling, settings
keys, or Codable formats. Surface failures instead of silently reporting success.

## Project and documentation

Add new files under the matching source boundary and include them in their owning
Xcode target exactly once. Do not duplicate future framework sources in the app
target. Resources belong under `Resources`; do not copy Info.plist
into the resources build phase. Keep the shared scheme checked in and personal
Xcode settings and build artifacts out of Git.

Update the appropriate guide for changes to build steps, behavior, or
architecture. Keep README as the entry point, with longer guidance in `docs/`.
Avoid claiming future work or unverified releases as shipped functionality.

Retain the MIT license and all applicable upstream notices. For third-party code
or artwork, verify licensing first and record repository, revision, relevant
paths, and attribution in the change and related documentation.

## Function inputs and unit tests

When adding or changing production code, audit every input: arguments, decoded
settings, HID report data, UI and system callbacks, timestamps, arithmetic, and
values returned by collaborators. State each supported range and any caller-owned
invariant at the appropriate boundary. Prefer constrained types when they
guarantee validity; otherwise validate before indexing, numeric conversion,
scheduling, and native side effects. Check nonfinite values, sign, overflow,
empty or malformed data, and range endpoints where relevant. Report invalid
input through the existing error or logging path; do not silently coerce valid
values, invent limits, reset settings, or change decoding fallbacks.

Add focused tests for new or changed input-bearing behavior to `MacDialKitTests`:

- Exercise representative valid inputs, exact endpoints, values just outside
  them, and extreme/nonfinite values when the type permits them.
- Cover malformed, missing, old, and round-tripped settings without changing
  keys, raw values, or fallback semantics; verify invalid input does not corrupt
  later valid input or gesture/timer state.
- Test ordering and interactions, such as press/rotate/release, cancellation,
  direction changes, and exact timer boundaries. Advance the test clock rather
  than sleeping or accessing real hardware.
- Exercise every new validation and fallback branch. Avoid tests of trivial
  accessors or guarantees already enforced by the language or a documented
  caller invariant. Coverage helps find omissions but is not a substitute for
  behavioral assertions.

Use a narrowly scoped pure seam for native logic when practical without moving
device/report ownership or duplicating source membership. The hostless suite
does not execute IOKit callbacks, AppKit/SwiftUI, Bluetooth, permissions, or
generated system events; list untested native paths and run the applicable
hardware/UI checks separately. Run the shared scheme as described in
[building](building.md#unit-tests).

## Validation checklist

- Build the shared `MacDial` scheme for the configuration you changed; check both
  Debug and Release when changing project settings or packaging.
- Inspect the packaged executable architecture, version, bundle identifier,
  app icon, minimum OS, menu-bar flag, privacy metadata, and local signature.
- Confirm each Swift source and resource has exactly one target membership.
- Add focused automated regression tests when changing behavior. Run the
  hostless `MacDialKitTests` target through the shared scheme, with coverage
  when changing core logic; see [unit test commands](building.md#unit-tests).
  Advance the test clock instead of sleeping or accessing real hardware.
- With a Surface Dial, check pairing/connection, rotation and pressed rotation,
  click/double-click/hold, mode selection, haptics, sleep/wake, and disconnect.
- Check settings save/reload and older exports, Accessibility/Input Monitoring/
  Bluetooth permissions, menu-bar/settings-window lifecycle, and launch at login.
- For UI changes, exercise supported macOS versions, light/dark appearance, and
  accessibility. State hardware or OS limits instead of implying those checks
  were performed.
