import XCTest
@testable import MacDialKit

final class DialModeIconTests: XCTestCase {
    func testLegacyScrollIconMigratesToCustomSymbol() throws {
        let data = Data("""
        {"modes":[{"name":"Scroll","icon":"scroll"}]}
        """.utf8)

        let config = try JSONDecoder().decode(DialConfig.self, from: data)

        XCTAssertEqual(config.modes.first?.icon, DialMode.scrollIcon)
    }

    func testPreviousScrollSymbolsMigrateWithoutChangingOtherSettings() throws {
        for icon in ["scroll", "scrollable-list"] {
            var original = DialConfig()
            original.modes = [
                DialMode(name: "Custom scroll", icon: icon, enabled: false,
                         rotate: RotationBinding(.scrollHorizontal, speed: 2),
                         click: ClickBinding(.rightClick)),
                DialMode(name: "Custom volume", icon: "star.fill"),
            ]
            original.currentModeID = original.modes[1].id
            original.stepsPerRevolution = 45
            let data = try JSONEncoder().encode(original)
            var expected = original
            expected.modes[0].icon = DialMode.scrollIcon

            let decoded = try JSONDecoder().decode(DialConfig.self, from: data)

            XCTAssertEqual(decoded, expected, icon)
            let reloaded = try JSONDecoder().decode(DialConfig.self, from: JSONEncoder().encode(decoded))
            XCTAssertEqual(reloaded, decoded, icon)
        }
    }

    func testCurrentCustomAndUnrecognizedIconNamesRemainUnchanged() throws {
        for icon in ["scroll-circular-arrows", "speaker.wave.2.fill", "custom-symbol",
                     "", "Scroll", "scrollable-list.custom"] {
            var original = DialConfig()
            original.modes = [DialMode(name: "My mode", icon: icon)]

            let decoded = try JSONDecoder().decode(DialConfig.self, from: JSONEncoder().encode(original))

            XCTAssertEqual(decoded, original, icon)
        }
    }

    func testLoadingPreviousSymbolDoesNotRewriteStoredDocument() throws {
        let suiteName = "MacDialIconTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var original = DialConfig()
        original.modes = [DialMode(name: "Scroll", icon: "scrollable-list")]
        let data = try JSONEncoder().encode(original)
        defaults.set(data, forKey: DialConfigStorage.key)

        let storage = DialConfigStorage(defaults: defaults)

        XCTAssertNil(storage.recovery)
        XCTAssertEqual(storage.loadedConfig.modes.first?.icon, DialMode.scrollIcon)
        XCTAssertEqual(defaults.data(forKey: DialConfigStorage.key), data)
        try storage.save(storage.loadedConfig)
        let reloaded = DialConfigStorage(defaults: defaults)
        XCTAssertNil(reloaded.recovery)
        XCTAssertEqual(reloaded.loadedConfig, storage.loadedConfig)
    }
}
