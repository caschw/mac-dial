# Agent guidance

## Purpose and lineage

Mac Dial is a native macOS Surface Dial utility. Its lineage is the original
[andreasjhkarlsson/mac-dial](https://github.com/andreasjhkarlsson/mac-dial) and the
Apple Silicon foundation from
[camerondehart/mac-dial-AppleSilicon](https://github.com/camerondehart/mac-dial-AppleSilicon).
Preserve native, event-driven IOKit HID input and CoreBluetooth wake support.
Keep the application primarily SwiftUI; use AppKit where macOS lifecycle,
menu-bar integration, windows, and system input require it.

[diversifiedfun/mac-dial](https://github.com/diversifiedfun/mac-dial) is a planned
source of visual and feature inspiration, especially its dial-menu look and feel.
Treat UI redesigns and feature ports as separate, reviewed changes with explicit
requirements, license review, and appropriate attribution. Do not imply that
planned features already exist.

## Architecture and compatibility

- Read [docs/architecture.md](docs/architecture.md) before changing boundaries.
- Keep device/report handling and concrete platform adapters in `MacDial`,
  testable configuration, gestures, and rotation selection in `MacDialKit`,
  and lifecycle/composition in `App`. Preserve the `Device`, `Input`, `Actions`,
  `Settings`, and `UI` responsibility boundaries described in the architecture.
- Preserve macOS 14 support, native Apple Silicon execution, menu-bar behavior,
  permissions, and `local.macdial.MacDial` unless a task explicitly changes them.
- Do not reset settings when changing the app version. Preserve the
  `dialConfig.v2` and `dialPeripheralIdentifier` keys, Codable schema, enum raw
  values, and fallback decoding behavior; design and document migrations first.
- Keep the checked-in Xcode project authoritative. Include each Swift file
  exactly once in its owning target's Compile Sources phase, keep resource
  membership correct, and keep the shared `MacDial` scheme usable. MacDialKit
  sources belong in the framework target, not duplicated in the app or tests.
  Do not reintroduce a parallel SwiftPM or shell build.

## Swift and documentation standards

Follow Apple's [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
and [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/).
Prefer clear names, narrow responsibilities, value types for models and SwiftUI
views, and explicit ownership and access control. Use native frameworks before
adding dependencies. Avoid speculative abstractions and unrelated formatting.

Respect the existing main-run-loop HID callbacks and main-queue UI updates.
Do not silently change callback isolation, gesture timing, haptics, or permission
handling as part of a presentation change. Surface errors through the existing
appropriate UI or logging paths.

Update the relevant `docs/` guide when behavior, architecture, or build steps
change. Keep README concise, distinguish plans from shipped functionality, and
retain original copyright notices and MIT terms. Record source and license
information for copied code or assets; a link alone is not license permission.

## Validation

Use the shared scheme and [docs/building.md](docs/building.md). Build the affected
configuration, check source/resource membership and packaged app metadata, and
add focused tests for new behavior in the hostless MacDialKitTests target;
do not report build or unit-test success as a hardware or UI test. Use the contribution
checklist and state Surface Dial, permission, and macOS-version limits explicitly.
