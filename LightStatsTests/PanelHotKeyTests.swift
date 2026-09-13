import Carbon
import XCTest
@testable import Light_Stats

final class PanelHotKeyTests: XCTestCase {
    func testDefaultIsControlOptionCommandU() {
        let hotKey = PanelHotKey.default
        XCTAssertEqual(hotKey.keyCode, 32)
        XCTAssertEqual(hotKey.displayKey, "U")
        XCTAssertEqual(hotKey.displayTitle, "⌃⌥⌘U")
        XCTAssertTrue(hotKey.hasModifier)
    }

    func testRawValueRoundTrip() {
        let original = PanelHotKey(
            keyCode: 8,
            modifiers: PanelHotKey.controlModifier | PanelHotKey.shiftModifier,
            displayKey: "C"
        )
        let restored = PanelHotKey(rawValue: original.rawValue)
        XCTAssertEqual(restored, original)
    }

    func testMalformedRawValueIsNil() {
        XCTAssertNil(PanelHotKey(rawValue: ""))
        XCTAssertNil(PanelHotKey(rawValue: "v1|32|1"))
        XCTAssertNil(PanelHotKey(rawValue: "v2|32|1|U"))
    }

    func testCarbonModifiersMatchCarbonFlags() {
        let combo = PanelHotKey.controlModifier | PanelHotKey.optionModifier | PanelHotKey.commandModifier
        let carbon = PanelHotKeyService.carbonModifiers(combo)
        XCTAssertEqual(carbon & UInt32(controlKey), UInt32(controlKey))
        XCTAssertEqual(carbon & UInt32(optionKey), UInt32(optionKey))
        XCTAssertEqual(carbon & UInt32(cmdKey), UInt32(cmdKey))
        XCTAssertEqual(carbon & UInt32(shiftKey), 0)
    }
}
