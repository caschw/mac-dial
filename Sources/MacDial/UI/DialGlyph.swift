import AppKit
import MacDialKit

enum DialGlyph {
    static func menuBarImage(_ style: MenuBarGlyph, modeIcon: String) -> NSImage? {
        let assetName: String
        switch style {
        case .twoTone:
            assetName = "MenuBarOrbitDial"
        case .outline:
            assetName = "MenuBarOrbitOutline"
        case .solid:
            assetName = "MenuBarOrbitSolid"
        case .color:
            assetName = "MenuBarOrbitColor"
        case .modeIcon:
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let image = MacDialIcon.image(named: modeIcon, configuration: configuration) {
                image.isTemplate = modeIcon != MacDialIcon.scrollCircularArrows
                return image
            }
            NSLog("MacDial: unable to load mode symbol %@; using the Orbit glyph", modeIcon)
            return menuBarImage(.twoTone, modeIcon: modeIcon)
        }

        guard let image = NSImage(named: NSImage.Name(assetName))?.copy() as? NSImage else {
            NSLog("MacDial: unable to load bundled menu-bar asset %@", assetName)
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = style != .color
        image.accessibilityDescription = "Mac Dial"
        return image
    }

    static func appIcon() -> NSImage? {
        guard let image = NSImage(named: NSImage.Name("AppIcon")) else {
            NSLog("MacDial: unable to load the named AppIcon asset from the app bundle")
            return nil
        }
        return image
    }

    static func writePNG(_ image: NSImage, size: Int, to url: URL) throws {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
