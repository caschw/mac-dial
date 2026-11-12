# Building and local installation

## Prerequisites

Install full Xcode with a macOS SDK that provides SwiftUI's macOS 26
`glassEffect` API, and complete its first-launch setup. Command Line Tools alone
cannot build the checked-in application project. **Xcode 27.2 (27B52) has been
verified**; a minimum supported Xcode version has not been established.

The app and MacDialKit share a **macOS 26.0 deployment target**, so Liquid Glass
APIs such as `glassEffect` are used directly without availability checks or a
legacy material fallback. Earlier macOS versions are not supported; users on
macOS 14 or 15 must keep an earlier build. Settings data is unchanged and stays
compatible.

Check the selected toolchain with:

```sh
xcodebuild -version
xcode-select -p
```

If needed, select your installed Xcode in **Xcode > Settings > Locations > Command
Line Tools**. Confirm that the selected Xcode includes the required SDK.
Apple Silicon is the primary development platform; hardware-validation limits
are described below.

## Xcode

Open `MacDial.xcodeproj`, select the shared **MacDial** scheme and **My Mac**, and
build or run. The project includes the app, the embedded MacDialKit framework,
the MacDialKitTests unit-test target, and the icon asset catalog.
The checked-in Xcode project is the authoritative build definition; no dependency
installation is required.

Both Debug and Release use marketing version `1.0`, build `1`, bundle identifier
`local.macdial.MacDial`, and executable `MacDial` inside `Mac Dial.app`.
`Resources/Info.plist` expands the target build settings. The deployment target
is macOS 26.0 for every target.

## Command line

From the repository root, build a locally signed app on an Apple Silicon Mac:

```sh
xcodebuild \
  -project MacDial.xcodeproj \
  -scheme MacDial \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- \
  build
```

The result is `build/DerivedData/Build/Products/Release/Mac Dial.app`.
Use `-configuration Debug` for a development build. Debug builds the active
architecture; Release uses standard macOS architectures and can produce a
universal arm64/x86_64 app. The destination selects an Apple Silicon Mac, not an
arm64-only Release binary. Native Apple Silicon execution does not require
Rosetta; Intel hardware behavior still needs separate validation.

The default signing identity is **Sign to Run Locally** (ad-hoc); no paid
developer account is needed for local development. Distribution signing,
notarization, and release publication are separate work and are not provided by
these instructions.

## Install and permissions

Quit an existing copy before replacing it. In Finder, copy the built app to
Applications, then open that copy. Installation and launch are intentionally
manual; the build does not terminate running apps, overwrite Applications, or
reset privacy permissions.

Grant Accessibility in **System Settings > Privacy & Security > Accessibility**
for generated events, Input Monitoring if requested for HID input, and Bluetooth
for instant wake. Ad-hoc rebuilds can invalidate existing permission grants. If
input stops working, remove the stale app entry and grant access to the installed
copy again. Avoid running multiple copies of the app against the same dial.

See [usage](usage.md) for pairing and [security](../SECURITY.md) for trust and
permission details.

## Unit tests

Use **Product > Test** with the shared MacDial scheme, or run:

```sh
xcodebuild \
  -project MacDial.xcodeproj \
  -scheme MacDial \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  -enableCodeCoverage YES \
  -resultBundlePath build/MacDialTests.xcresult \
  CODE_SIGN_IDENTITY=- \
  test

xcrun xccov view --report build/MacDialTests.xcresult
```

Choose a fresh result-bundle path for each run. These are hostless framework
tests: the app is built, but is not launched as a test host, so tests neither
open hardware services nor require Accessibility, Bluetooth, or Input Monitoring
permission. A controllable test scheduler advances gesture timers synchronously.
Coverage for the app's native integrations and UI is not implied by framework
coverage: the native HID callback, system-event generation, Bluetooth, and
SwiftUI/AppKit settings and menus are not executed. The pure HID report decoder
is covered independently. Include invalid inputs,
boundaries, stateful interactions, and saved-configuration compatibility in
focused tests; see [function input requirements](contributing.md#function-inputs-and-unit-tests).
There is no SwiftPM or alternate shell build.

## Verification

After building:

```sh
plutil -p 'build/DerivedData/Build/Products/Release/Mac Dial.app/Contents/Info.plist'
file 'build/DerivedData/Build/Products/Release/Mac Dial.app/Contents/MacOS/MacDial'
codesign --verify --deep --strict 'build/DerivedData/Build/Products/Release/Mac Dial.app'
otool -L 'build/DerivedData/Build/Products/Release/Mac Dial.app/Contents/MacOS/MacDial'
```

Check version `1.0`, build `1`, the bundle identifier and executable above,
`LSUIElement = true`, `LSMinimumSystemVersion` 26.0, the Bluetooth usage description, and
`AppIcon.icns` in `Contents/Resources`. In Xcode, each source should occur once in
its owning target's Compile Sources and the asset catalog once in the app's Copy
Bundle Resources; Info.plist is a build input, not a copied resource.
Confirm `Contents/Frameworks/MacDialKit.framework` is present and the executable
links `@rpath/MacDialKit.framework/Versions/A/MacDialKit`.

Successful framework tests and builds do not verify the
permissions workflow, launch at login, Surface Dial connection, wake, haptics,
gestures, or appearance on macOS 26. Use the hardware checklist in
[contributing](contributing.md) and report what was actually exercised.
