import AppKit
import SwiftUI

enum MacDialIcon {
    static let scrollableList = "scrollable-list"

    static func image(named name: String, accessibilityDescription: String? = nil) -> NSImage? {
        if name == scrollableList {
            return NSImage(named: NSImage.Name(name))
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
    }
}

struct MacDialIconView: View {
    let name: String
    var primary: Color = .primary
    var secondary: Color = .accentColor

    var body: some View {
        if name == MacDialIcon.scrollableList {
            Image(name)
                .symbolRenderingMode(.palette)
                .foregroundStyle(primary, secondary)
        } else {
            Image(systemName: name)
                .foregroundStyle(primary)
        }
    }
}
