# Building and local installation

## Prerequisites

Install full Xcode with a macOS SDK and complete its first-launch setup. Command
Line Tools alone cannot build the checked-in application project. Check the
selected toolchain with:

```sh
xcodebuild -version
xcode-select -p
```

If needed, select your installed Xcode in **Xcode > Settings > Locations > Command
Line Tools**. Use an Xcode release that can compile the source and build for
macOS 14 or later; newer appearance APIs are availability-gated in the source.
Apple Silicon is the primary development and hardware-validation platform.

## Xcode

Open `MacDial.xcodeproj`, select the shared **MacDial** scheme and **My Mac**, and
build or run. The project includes all Swift sources and the icon asset catalog.
It replaces the previous SwiftPM and shell build; no dependency installation is
required.

Both Debug and Release use marketing version `1.0`, build `1`, bundle identifier
`local.macdial.MacDial`, and executable `MacDial` inside `Mac Dial.app`.
`Resources/Info.plist` expands the target build settings. The deployment target
is macOS 14.0.

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

## Verification

After building:

```sh
plutil -p 'build/DerivedData/Build/Products/Release/Mac Dial.app/Contents/Info.plist'
file 'build/DerivedData/Build/Products/Release/Mac Dial.app/Contents/MacOS/MacDial'
codesign --verify --deep --strict 'build/DerivedData/Build/Products/Release/Mac Dial.app'
```

Check version `1.0`, build `1`, the bundle identifier and executable above,
`LSUIElement = true`, minimum macOS 14.0, the Bluetooth usage description, and
`AppIcon.icns` in `Contents/Resources`. In Xcode, each source should occur once in
Compile Sources and the asset catalog once in Copy Bundle Resources; Info.plist
is a build input, not a copied resource.

There is no automated test target yet. A successful build does not verify the
permissions workflow, launch at login, Surface Dial connection, wake, haptics,
gestures, or macOS 14 runtime compatibility. Use the hardware checklist in
[contributing](contributing.md) and report what was actually exercised.
