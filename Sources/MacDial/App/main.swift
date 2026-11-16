import AppKit

let arguments = CommandLine.arguments

// `MacDial --render-icon <path.png>` exports a snapshot of the named app icon and exits.
if let index = arguments.firstIndex(of: "--render-icon"), index + 1 < arguments.count {
    do {
        guard let icon = DialGlyph.appIcon() else { exit(1) }
        try DialGlyph.writePNG(icon, size: 1024, to: URL(fileURLWithPath: arguments[index + 1]))
        exit(0)
    } catch {
        fputs("Failed to render icon: \(error)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
