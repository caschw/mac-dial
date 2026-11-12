# Using Mac Dial

**Surface Dial support for macOS, rebuilt natively for Apple Silicon.**

macOS can pair with a Microsoft Surface Dial, but it turns the dial's input into broken mouse events. Mac Dial reads the dial directly and turns it into whatever you want: scrolling, volume, switching desktops, keyboard shortcuts, clicks, and more. It also brings back the Surface Dial's **press-and-hold radial menu** for switching between tools.

For project lineage, licensing, and development documentation, see the [README](../README.md).

---

## Features

- **Native on Apple Silicon.** No third-party libraries. Dial input is event driven through Apple's IOKit.
- **Modes**, like the Surface Dial's "tools." Create as many as you like, and give each one its own:
  - **Turn** action
  - **Turn while pressed** action (hold the dial down and turn it)
  - **Click**, **double-click**, and **press & hold** actions
- **Radial menu.** Press and hold the dial to open it, turn to highlight a mode, and click to choose it. The translucent glass dial marks the selected wedge with an accent along its outer edge; the center shows the highlighted name and what a click will do.
- **Haptic feedback**: ticks while turning, plus a buzz when you change modes or move through the menu.
- **Liquid Glass** radial menu and HUD, in light and dark mode. The menu respects Reduce Transparency, Reduce Motion, and Increase Contrast.
- **Modern settings window** built with SwiftUI.
- **Dial menu bar icon** in four styles (Dial, Outline, Solid, Color), or the current mode's icon. Pick one in Settings › Appearance.
- Adjustable sensitivity, gesture timing, an on-screen label when you switch modes, and an option to open at login.

### What turning can do

| | |
|---|---|
| Scroll up/down or left/right | Smooth scrolling that speeds up the faster you spin |
| Volume | Fine ¼-step control; follows macOS by default, or your chosen Volume Output |
| Display brightness | Apple displays only |
| Switch desktops (Spaces) | ⌃← / ⌃→ |
| Switch apps | Holds ⌘⇥ while you turn, then click or pause to pick |
| Switch tabs, zoom, undo/redo | |
| Previous / next track | |
| Arrow keys | ← → or ↑ ↓ |
| Custom | Any keyboard shortcut for each direction |

To keep controls responsive, a rotation that would leave more than 4,096 system
events pending is ignored and logged. Normal settings produce at most 512 events
per dial report.

### What pressing can do

Left, right, or middle click · double click · play/pause · mute · next/previous track · Mission Control · show desktop · app windows · open the radial menu · next mode · any keyboard shortcut · open an app

If a mode only uses a mouse click, with no double-click, press & hold, or turn-while-pressed action, the dial acts as a real mouse button. You can hold it down to drag things.

### Default modes

| Mode | Turn | Turn while pressed | Click | Double-click |
|---|---|---|---|---|
| Scroll | Scroll | Horizontal scroll | Left click | – |
| Volume | Volume | Prev / next track | Play / pause | Next track |
| Desktops | Switch Spaces | Switch apps | Mission Control | Show desktop |
| Zoom | Zoom in / out | – | Reset zoom (⌘0) | – |
| Undo | Undo / redo | – | – | – |
| Brightness *(off by default)* | Brightness | – | – | – |
| Volume Output | Select an output in the secondary arc; then return to your previous mode | – | Confirm output | – |

In ordinary modes, **press & hold** opens the radial menu. Everything can be changed in Settings.

### Radial menu

Turn to move the highlight and click to choose. The menu closes after six
seconds of inactivity, or when the enabled modes or sensitivity change while it
is open.

The menu supports nested items: clicking an item marked with a chevron opens an
outer glass arc attached directly to the circle with that item's options. The
arc starts with a **Back** item; clicking it returns to the previous level. Long submenus show up
to seven options at once, with dots at either end when more are available.
**Volume Output** opens a secondary arc containing available outputs that
support software volume control. Device discovery stays live while the app and
menu are open. An output selection closes the menu, shows
**Volume output changed to [device name]** (when on-screen labels are enabled),
and silently returns to your previous operating mode. Back, timeout, and
dismissal do not change the volume target.

### Volume Output

This utility selects which device **Mac Dial's Volume actions** adjust. It does
**not** change macOS's default output or route audio from other apps. For example,
selecting headphones only changes their volume; it does not move currently
playing audio to them. Without a selected device, volume uses the existing
system-volume keys and native HUD. An explicitly selected device uses Core Audio
directly and does not display the native macOS volume HUD. Mute and media actions
keep their existing system-wide behavior.

Settings > **Volume Output** lists live sound outputs. **Disable** only hides a
device from the dial arc; it does not disconnect it, change routing, or clear a
selected target. **Disabled Outputs** always retains locally remembered devices,
including disconnected ones, with an **Enable** button. New and returning devices
appear automatically unless disabled. Devices without software volume control
remain visible in Settings but are excluded from the arc.

If a selected device disconnects, volume temporarily follows macOS's current
output and resumes the remembered device when it returns. If the device remains
connected but cannot be adjusted, Mac Dial reports an error instead of silently
changing another output. **Follow macOS Output** clears the explicit selection.

Volume Output is added once to new and existing installations without changing
custom modes or bindings. You can rename it, choose its icon (default:
`speaker.wave.2.circle`), hide it from the dial, or delete it. A deleted utility
stays deleted across launches; the **+** menu in Settings can add it again.
Selecting it from Settings or the menu bar also opens its arc.
With a Next Mode binding, the next activation advances past this one-shot
utility instead of repeatedly opening it.

---

## Set up the app

**Requires macOS 26 Tahoe or later.** Built for Apple Silicon Macs.

1. [Build from source](building.md), then copy **Mac Dial.app** to your **Applications** folder.
2. Open it. Local builds are ad-hoc signed, not notarized. Only approve a build you trust if macOS asks you to review it in **System Settings > Privacy & Security**.
3. Grant **Accessibility** access when asked (**System Settings > Privacy & Security > Accessibility**). Mac Dial needs it to send scrolls, clicks, and keystrokes.

### Pair your Surface Dial

1. Open the battery cover and hold the button next to the batteries until the light blinks.
2. In **System Settings › Bluetooth**, connect to **Surface Dial**.
3. A dial icon appears in the menu bar. Click it and choose **Settings…** to set up your modes.

If Settings warns that saved settings cannot be fully understood, the original
remains unchanged and edits are temporary. Use **Export Original…** to keep a
copy, then **Replace Saved Settings…** only if you want to save the settings
currently shown. If another instance changes the saved settings, Mac Dial
protects the newer value and asks for confirmation again.

### Tips

- **Open at login:** Settings › General › *Open Mac Dial at login*.
- **Instant wake:** when the dial goes to sleep, Mac Dial has your Mac listen for it so it reconnects as soon as you press or turn it. Allow **Bluetooth** access when asked. You can turn this off in Settings › General › *Wake instantly from sleep*.
- **Switch desktops** needs the ⌃← / ⌃→ shortcuts turned on in **System Settings › Keyboard › Keyboard Shortcuts › Mission Control**.
- **Brightness** only affects Apple displays.
- **Switch modes** from the radial menu (press & hold), or from the menu bar icon.
