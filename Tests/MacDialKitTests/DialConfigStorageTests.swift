import XCTest
import MacDialKit

final class DialConfigStorageTests: XCTestCase {
    func testMissingAndLegacySettingsRemainWritable() throws {
        try withDefaults { defaults in
            XCTAssertNil(DialConfigStorage(defaults: defaults).recovery)
            defaults.set(Data(#"{"stepsPerRevolution":45}"#.utf8), forKey: DialConfigStorage.key)
            let storage = DialConfigStorage(defaults: defaults)
            XCTAssertNil(storage.recovery)
            var config = storage.loadedConfig
            XCTAssertEqual(config.stepsPerRevolution, 45)
            config.showHUD = false
            try storage.save(config)
            let saved = try XCTUnwrap(defaults.data(forKey: DialConfigStorage.key))
            XCTAssertEqual(try JSONDecoder().decode(DialConfig.self, from: saved), config)
        }
    }

    func testMalformedAndIncompatibleDocumentsCannotBeOverwrittenByOrdinaryEdits() throws {
        let valid = try JSONEncoder().encode(DialConfig())
        let futureAction = try XCTUnwrap(String(data: valid, encoding: .utf8))
            .replacingOccurrences(of: #""scrollVertical""#, with: #""futureAction""#)
        let documents = [
            Data("{".utf8),
            Data("[]".utf8),
            Data(#"{"modes":[{"name":"incomplete"}]}"#.utf8),
            Data(#"{"fastWake":"invalid"}"#.utf8),
            Data(#"{"menuBarGlyph":"future"}"#.utf8),
            Data(futureAction.utf8)
        ]
        try withDefaults { defaults in
            for original in documents {
                defaults.set(original, forKey: DialConfigStorage.key)
                let storage = DialConfigStorage(defaults: defaults)
                XCTAssertNotNil(storage.recovery)
                XCTAssertEqual(storage.recovery?.originalData, original)
                var edited = storage.loadedConfig
                edited.showHUD.toggle()
                XCTAssertThrowsError(try storage.save(edited))
                XCTAssertEqual(defaults.data(forKey: DialConfigStorage.key), original)
            }
        }
    }

    func testUnknownFieldsAtRootAndInsideBindingsAreProtected() throws {
        let encoded = try JSONEncoder().encode(DialConfig())
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        root["futureSetting"] = true
        let rootExtra = try JSONSerialization.data(withJSONObject: root)
        root.removeValue(forKey: "futureSetting")
        var modes = try XCTUnwrap(root["modes"] as? [[String: Any]])
        var rotation = try XCTUnwrap(modes[0]["rotate"] as? [String: Any])
        rotation["futureOption"] = 42
        modes[0]["rotate"] = rotation
        root["modes"] = modes
        let nestedExtra = try JSONSerialization.data(withJSONObject: root)

        try withDefaults { defaults in
            for (data, expectedPath) in [(rootExtra, "futureSetting"), (nestedExtra, "modes[0].rotate.futureOption")] {
                defaults.set(data, forKey: DialConfigStorage.key)
                let storage = DialConfigStorage(defaults: defaults)
                XCTAssertTrue(storage.recovery?.reason.contains(expectedPath) == true)
                XCTAssertThrowsError(try storage.save(storage.loadedConfig))
                XCTAssertEqual(defaults.data(forKey: DialConfigStorage.key), data)
            }
        }
    }

    func testExplicitNullForKnownOptionalFieldsRemainsCompatible() throws {
        let encoded = try JSONEncoder().encode(DialConfig())
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        root["currentModeID"] = NSNull()
        var modes = try XCTUnwrap(root["modes"] as? [[String: Any]])
        var rotation = try XCTUnwrap(modes[0]["rotate"] as? [String: Any])
        rotation["clockwise"] = NSNull()
        modes[0]["rotate"] = rotation
        var click = try XCTUnwrap(modes[0]["click"] as? [String: Any])
        click["appPath"] = NSNull()
        modes[0]["click"] = click
        root["modes"] = modes
        let data = try JSONSerialization.data(withJSONObject: root)
        try withDefaults { defaults in
            defaults.set(data, forKey: DialConfigStorage.key)
            XCTAssertNil(DialConfigStorage(defaults: defaults).recovery)
        }
    }

    func testReplacementRequiresSuccessfulEncodingAndClearsProtection() throws {
        try withDefaults { defaults in
            let original = Data(#"{"modes":[{"action":"future"}]}"#.utf8)
            defaults.set(original, forKey: DialConfigStorage.key)
            let storage = DialConfigStorage(defaults: defaults)
            var replacement = storage.loadedConfig
            replacement.doubleClickInterval = .nan
            XCTAssertThrowsError(try storage.replaceSavedSettings(with: replacement))
            XCTAssertNotNil(storage.recovery)
            XCTAssertEqual(defaults.data(forKey: DialConfigStorage.key), original)

            replacement.doubleClickInterval = 0.4
            try storage.replaceSavedSettings(with: replacement)
            XCTAssertNil(storage.recovery)
            let saved = try XCTUnwrap(defaults.data(forKey: DialConfigStorage.key))
            XCTAssertEqual(try JSONDecoder().decode(DialConfig.self, from: saved), replacement)
            XCTAssertNil(DialConfigStorage(defaults: defaults).recovery)
        }
    }

    func testUnexpectedUserDefaultsTypeIsProtectedAndCanBeExported() throws {
        try withDefaults { defaults in
            defaults.set("not data", forKey: DialConfigStorage.key)
            let storage = DialConfigStorage(defaults: defaults)
            XCTAssertNotNil(storage.recovery)
            XCTAssertNotNil(storage.recovery?.originalData)
            XCTAssertThrowsError(try storage.save(storage.loadedConfig))
            XCTAssertEqual(defaults.string(forKey: DialConfigStorage.key), "not data")
        }
    }

    func testStaleStoreProtectsSettingsWrittenByAnotherInstance() throws {
        try withDefaults { defaults in
            let first = DialConfigStorage(defaults: defaults)
            let stale = DialConfigStorage(defaults: defaults)
            var firstConfig = first.loadedConfig
            firstConfig.showHUD = false
            try first.save(firstConfig)
            let original = try XCTUnwrap(defaults.data(forKey: DialConfigStorage.key))

            XCTAssertThrowsError(try stale.save(stale.loadedConfig)) {
                XCTAssertEqual($0 as? DialConfigStorage.SaveError, .changedSettings)
            }
            XCTAssertEqual(defaults.data(forKey: DialConfigStorage.key), original)
            XCTAssertEqual(stale.recovery?.originalData, original)
            XCTAssertThrowsError(try stale.save(stale.loadedConfig)) {
                XCTAssertEqual($0 as? DialConfigStorage.SaveError, .protectedSettings)
            }
            try stale.replaceSavedSettings(with: stale.loadedConfig)
            XCTAssertNil(stale.recovery)
            XCTAssertEqual(try JSONDecoder().decode(DialConfig.self, from: XCTUnwrap(defaults.data(forKey: DialConfigStorage.key))),
                           stale.loadedConfig)
        }
    }

    func testReplacementChecksForChangesSinceTheLastRecoveryNotice() throws {
        try withDefaults { defaults in
            let first = Data(#"{"futureSetting":true}"#.utf8)
            let second = Data(#"{"futureSetting":"newer"}"#.utf8)
            defaults.set(first, forKey: DialConfigStorage.key)
            let storage = DialConfigStorage(defaults: defaults)
            defaults.set(second, forKey: DialConfigStorage.key)
            XCTAssertThrowsError(try storage.replaceSavedSettings(with: storage.loadedConfig)) {
                XCTAssertEqual($0 as? DialConfigStorage.SaveError, .changedSettings)
            }
            XCTAssertEqual(defaults.data(forKey: DialConfigStorage.key), second)
            XCTAssertEqual(storage.recovery?.originalData, second)
            try storage.replaceSavedSettings(with: storage.loadedConfig)
            XCTAssertNil(storage.recovery)
        }
    }

    func testUnknownDocumentWrittenAfterInitializationIsProtected() throws {
        try withDefaults { defaults in
            let storage = DialConfigStorage(defaults: defaults)
            let future = Data(#"{"futureSetting":true}"#.utf8)
            defaults.set(future, forKey: DialConfigStorage.key)
            XCTAssertThrowsError(try storage.save(storage.loadedConfig))
            XCTAssertEqual(defaults.data(forKey: DialConfigStorage.key), future)
            XCTAssertEqual(storage.recovery?.originalData, future)
            XCTAssertTrue(storage.recovery?.reason.contains("changed") == true)
        }
    }

    func testUnchangedUnsupportedPropertyListCanBeReplaced() throws {
        try withDefaults { defaults in
            defaults.set(["nested": ["name": "example"], "values": [1, 2]], forKey: DialConfigStorage.key)
            let storage = DialConfigStorage(defaults: defaults)
            XCTAssertNotNil(storage.recovery)
            try storage.replaceSavedSettings(with: storage.loadedConfig)
            XCTAssertNil(storage.recovery)
            XCTAssertNotNil(defaults.data(forKey: DialConfigStorage.key))
        }
    }

    func testReplacementDetectsChangedOrRemovedUnsupportedValues() throws {
        try withDefaults { defaults in
            defaults.set(true, forKey: DialConfigStorage.key)
            let storage = DialConfigStorage(defaults: defaults)
            defaults.set(2, forKey: DialConfigStorage.key)
            XCTAssertThrowsError(try storage.replaceSavedSettings(with: storage.loadedConfig))
            XCTAssertEqual(defaults.integer(forKey: DialConfigStorage.key), 2)
            XCTAssertNotNil(storage.recovery?.originalData)
            defaults.removeObject(forKey: DialConfigStorage.key)
            XCTAssertThrowsError(try storage.replaceSavedSettings(with: storage.loadedConfig))
            XCTAssertNil(storage.recovery?.originalData)
            XCTAssertNil(defaults.object(forKey: DialConfigStorage.key))
            try storage.replaceSavedSettings(with: storage.loadedConfig)
            XCTAssertNotNil(defaults.data(forKey: DialConfigStorage.key))
        }
    }

    func testOutOfRangeShortcutReportsTheFieldInsteadOfInvalidJSON() throws {
        var config = DialConfig()
        config.modes[0].rotate.clockwise = KeyShortcut(keyCode: 0, modifiers: 0, keyName: "test")
        let valid = try JSONEncoder().encode(config)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var modes = try XCTUnwrap(root["modes"] as? [[String: Any]])
        var rotate = try XCTUnwrap(modes[0]["rotate"] as? [String: Any])
        var shortcut = try XCTUnwrap(rotate["clockwise"] as? [String: Any])

        try withDefaults { defaults in
            for value in [-1, 65_536] {
                shortcut["keyCode"] = value
                rotate["clockwise"] = shortcut
                modes[0]["rotate"] = rotate
                root["modes"] = modes
                let data = try JSONSerialization.data(withJSONObject: root)
                defaults.set(data, forKey: DialConfigStorage.key)
                let storage = DialConfigStorage(defaults: defaults)
                let reason = try XCTUnwrap(storage.recovery?.reason)
                XCTAssertTrue(reason.contains("modes[0].rotate.clockwise.keyCode"), reason)
                XCTAssertFalse(reason.contains("not valid JSON"), reason)
                XCTAssertEqual(storage.recovery?.originalData, data)
            }
        }
        for value in [UInt16.min, UInt16.max] {
            let shortcut = KeyShortcut(keyCode: value, modifiers: UInt.max, keyName: "test")
            XCTAssertEqual(try JSONDecoder().decode(KeyShortcut.self, from: JSONEncoder().encode(shortcut)), shortcut)
        }
    }

    func testOutOfRangeShortcutModifiersAndRootValuesAreNotCalledInvalidJSON() throws {
        var config = DialConfig()
        config.modes[0].rotate.clockwise = KeyShortcut(keyCode: 0, modifiers: 0, keyName: "test")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(config), encoding: .utf8))
        let invalidModifiers = json.replacingOccurrences(of: #""modifiers":0"#,
                                                          with: #""modifiers":18446744073709551616"#)
        XCTAssertNotEqual(json, invalidModifiers)
        try withDefaults { defaults in
            defaults.set(Data(invalidModifiers.utf8), forKey: DialConfigStorage.key)
            let reason = try XCTUnwrap(DialConfigStorage(defaults: defaults).recovery?.reason)
            XCTAssertTrue(reason.contains("modes[0].rotate.clockwise.modifiers"), reason)
            XCTAssertFalse(reason.contains("not valid JSON"), reason)

            defaults.set(Data(#"{"stepsPerRevolution":9223372036854775808}"#.utf8),
                         forKey: DialConfigStorage.key)
            let rootReason = try XCTUnwrap(DialConfigStorage(defaults: defaults).recovery?.reason)
            XCTAssertFalse(rootReason.contains("not valid JSON"), rootReason)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "local.macdial.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
