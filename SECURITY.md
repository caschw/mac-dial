# Security Policy

## Reporting a vulnerability

Please **don't open a public issue** for security problems.

Use [GitHub private vulnerability reporting](https://github.com/caschw/mac-dial/security/advisories/new): open this repository's **Security** tab and choose **Report a vulnerability**. Include the affected commit or build, macOS version, reproduction steps, impact, and any proposed mitigation. Remove personal data and credentials from logs or attachments.

Coordinate disclosure privately with the maintainer. Do not publish exploit details in public issues or pull requests while a report is being assessed.

## What the app can access

Mac Dial asks for these permissions, and only uses them for the dial:

- **Accessibility**: to send the scroll, click, and keyboard events you set up for the dial.
- **Input Monitoring** (only if macOS asks): to read input from the Surface Dial over Bluetooth.
- **Bluetooth**: to reconnect to the paired dial for the optional instant-wake feature.

The app has no internet networking, analytics, or auto-updater. Bluetooth communication is local to the dial. Configuration and the remembered Bluetooth peripheral identifier are stored locally in `UserDefaults`. Exported settings files may contain your shortcuts and app paths; review them before sharing.

The application is not sandboxed because it reads HID input and generates system input. Grant permissions only to builds you trust.

## Verifying a download

The checked-in Xcode project uses ad-hoc signing for local builds; that is not a verified publisher identity or notarization. This repository change does not establish a new release artifact. Build from reviewed source using the [build guide](docs/building.md). Do not bypass macOS security prompts for binaries whose origin you cannot verify.
