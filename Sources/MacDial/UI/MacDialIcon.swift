import AppKit
import MacDialKit
import SwiftUI

enum MacDialIcon {
    static let scrollCircularArrows = DialMode.scrollIcon

    static func image(named name: String, accessibilityDescription: String? = nil,
                      configuration: NSImage.SymbolConfiguration? = nil) -> NSImage? {
        if name == scrollCircularArrows {
            // The symbol's down arrow is layer 0; its up arrow is layer 1.
            let palette = NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor, .labelColor])
            guard let image = NSImage(named: NSImage.Name(name))?
                .withSymbolConfiguration(configuration?.applying(palette) ?? palette) else {
                NSLog("MacDial: unable to configure bundled symbol %@", name)
                return nil
            }
            image.isTemplate = false
            image.accessibilityDescription = accessibilityDescription
            return image
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        if let configuration {
            return image?.withSymbolConfiguration(configuration)
        }
        return image
    }
}

struct MacDialIconView: View {
    let name: String
    var primary: Color = .primary

    var body: some View {
        if name == MacDialIcon.scrollCircularArrows {
            Image(name)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor), Color(nsColor: .labelColor))
        } else {
            Image(systemName: name)
                .foregroundStyle(primary)
        }
    }
}
