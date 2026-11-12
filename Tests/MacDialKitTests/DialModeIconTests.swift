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
}
