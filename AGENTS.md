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
- Keep device ownership and concrete platform adapters in `MacDial`, and report
  decoding, configuration and Foundation-backed persistence, gestures, and
  rotation selection in `MacDialKit`. Preserve the `Device`, `Input`, `Actions`,
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

For every new or changed function, identify each input's domain and its trust
boundary. Validate externally supplied, decoded, arithmetic, and callback values
before indexing, conversion, scheduling, or side effects; use constrained Swift
types or documented caller invariants when they already guarantee validity.
Handle malformed, missing, nonfinite, negative, out-of-range, and overflowing
values as applicable without inventing limits, silently dropping errors, changing
valid behavior, or rewriting saved configuration.

Add deterministic regression tests for meaningful valid inputs, both boundaries
and just-outside values, invalid inputs, stateful interactions, and settings
compatibility. Cover every new validation branch, including its effect on state.
Use the fake scheduler rather than sleeps. Where native code cannot reasonably
run in the hostless target, test a small pure seam when it respects the source
boundaries and explicitly report the remaining device/UI-only checks. See
[contributing](docs/contributing.md#function-inputs-and-unit-tests).
