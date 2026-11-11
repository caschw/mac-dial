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

## Validation checklist

- Build the shared `MacDial` scheme for the configuration you changed; check both
  Debug and Release when changing project settings or packaging.
- Inspect the packaged executable architecture, version, bundle identifier,
  app icon, minimum OS, menu-bar flag, privacy metadata, and local signature.
- Confirm each Swift source and resource has exactly one target membership.
- Add focused automated regression tests when changing behavior. No automated
  test target currently exists; planned testability work is tracked in
  [MacDialKit and behavior tests (#1)](https://github.com/caschw/mac-dial/issues/1).
- With a Surface Dial, check pairing/connection, rotation and pressed rotation,
  click/double-click/hold, mode selection, haptics, sleep/wake, and disconnect.
- Check settings save/reload and older exports, Accessibility/Input Monitoring/
  Bluetooth permissions, menu-bar/settings-window lifecycle, and launch at login.
- For UI changes, exercise supported macOS versions, light/dark appearance, and
  accessibility. State hardware or OS limits instead of implying those checks
  were performed.
