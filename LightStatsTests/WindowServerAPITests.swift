//
//  WindowServerAPITests.swift
//  Light Stats Tests
//
//  The two pure seams of the private WindowServer surface: the make-key event record's byte layout
//  and the "which Spaces are not showing" rule.
//
//  Both are pinned here because neither can be observed from the outside on every machine: a wrong
//  offset in the record still compiles and still makes *some* window key on *some* macOS version, and
//  a Spaces rule that treats an unknown Space as active quietly hides every window on another
//  desktop. The live switch itself is not testable — it moves the user's real windows and Spaces.
//

import CoreGraphics
import XCTest
@testable import Light_Stats

final class WindowServerAPITests: XCTestCase {

    // MARK: - Make-key event record

    /// The record as AltTab documents it: a 0x100-byte buffer whose declared length stays 0xf8, one
    /// left-mouse-down at 0x08, `0x10` at 0x3a, the target window id at 0x3c, and the click point at
    /// 0x20 — with nothing else set.
    func testRecordIsTheSkyLightEventRecordAtTheDocumentedOffsets() {
        var expected = [UInt8](repeating: 0, count: 0x100)
        expected[0x04] = 0xf8
        expected[0x08] = 0x01
        expected[0x3a] = 0x10
        expected[0x3c] = 0x34
        expected[0x3d] = 0x12
        expected[0x3e] = 0x00
        expected[0x3f] = 0x00
        expected.replaceSubrange(0x20..<0x30, with: doubleBytes(300_000) + doubleBytes(300_000))

        XCTAssertEqual(
            PrivateWindowServerAPI.MakeKeyEvent.record(windowID: 0x1234), expected,
            "the posted record must be a 0x100-byte buffer with the event fields at AltTab's offsets"
        )
    }

    /// The declared length stays 0xf8 while the buffer is 0x100 bytes: the WindowServer's encoder
    /// reads past 0xf8 (paneru#123), and a length that matched the buffer would change the event.
    func testBufferIsPaddedButDeclaresTheOriginalRecordLength() {
        let record = PrivateWindowServerAPI.MakeKeyEvent.record(windowID: 42)
        XCTAssertEqual(record.count, 0x100, "the buffer is widened, not the record")
        XCTAssertEqual(record[0x04], 0xf8, "the record must still declare its own 0xf8 length")
    }

    /// The event type is left-mouse-**down** and only that. A paired up completes a click, and a
    /// completed click activates whatever control it lands on.
    func testRecordCarriesTheLeftMouseDownType() {
        let record = PrivateWindowServerAPI.MakeKeyEvent.record(windowID: 42)
        XCTAssertEqual(record[0x08], 0x01, "a synthetic left mouse down is what makes a window key")
        XCTAssertEqual(PrivateWindowServerAPI.MakeKeyEvent.leftMouseDown, 0x01)
    }

    /// The click point is far outside any conceivable window: inside one, a sanitised value lands on
    /// content the app activates, and a few points outside sits in the resize grab region. Hence
    /// 300000 on both axes, well past a fullscreen window on a 6K display.
    func testClickPointIsFarOutsideAnyWindow() {
        let record = PrivateWindowServerAPI.MakeKeyEvent.record(windowID: 42)
        let point = PrivateWindowServerAPI.MakeKeyEvent.offContentPoint
        XCTAssertEqual(point.x, 300_000)
        XCTAssertEqual(point.y, 300_000)
        XCTAssertGreaterThan(point.x, 6_016, "wider than a fullscreen window on a Pro Display XDR")
        XCTAssertEqual(Array(record[0x20..<0x28]), doubleBytes(300_000), "x at 0x20")
        XCTAssertEqual(Array(record[0x28..<0x30]), doubleBytes(300_000), "y at 0x28")
    }

    /// The window id is what delivers the event — the coordinate only carries the point — so a window
    /// id whose high bytes are set must survive the little-endian write intact.
    func testWindowIDIsWrittenLittleEndianAt0x3c() {
        let record = PrivateWindowServerAPI.MakeKeyEvent.record(windowID: 0x00AB_CDEF)
        XCTAssertEqual(Array(record[0x3c..<0x40]), [0xEF, 0xCD, 0xAB, 0x00])
        XCTAssertEqual(
            PrivateWindowServerAPI.MakeKeyEvent.windowIDOffset, 0x3c,
            "the down is delivered to the window id at 0x3c, not to the click point"
        )
    }

    // MARK: - Inactive Spaces

    /// The plain case: one display showing one of its three Spaces, so the other two are inactive.
    func testSpacesOtherThanTheCurrentOneAreInactive() {
        let displays = [display(spaces: [1, 2, 3], current: 1)]
        XCTAssertEqual(
            PrivateWindowServerAPI.inactiveSpaceIDs(displays: displays, activeSpaceID: nil), [2, 3],
            "a window on a Space that is not showing is the case the switcher exists for"
        )
    }

    /// Every display has its own current Space, and a neighbour's is not inactive just because it is
    /// not the one on the main display.
    func testEachDisplayContributesItsOwnCurrentSpace() {
        let displays = [
            display(spaces: [1, 2], current: 2),
            display(spaces: [3, 4], current: 3)
        ]
        XCTAssertEqual(
            PrivateWindowServerAPI.inactiveSpaceIDs(displays: displays, activeSpaceID: nil), [1, 4],
            "one active Space per display: neither display's current Space is on another desktop"
        )
    }

    /// `SLSGetActiveSpace` covers a display dictionary that arrives without `Current Space` — without
    /// it every Space would read as inactive and every window would look like it is on another Space.
    func testSymbolActiveSpaceCoversADisplayWithoutItsOwnCurrentSpace() {
        let displays = [display(spaces: [5, 6, 7], current: nil)]
        XCTAssertEqual(
            PrivateWindowServerAPI.inactiveSpaceIDs(displays: displays, activeSpaceID: 6), [5, 7],
            "an unknown current Space must not turn every window into a cross-Space window"
        )
    }

    /// With neither answer available the whole topology reads inactive. That is the degraded direction
    /// on purpose: the merge only ever *adds* a card the user can act on, so an over-broad answer
    /// costs a card, never a window that cannot be reached.
    func testWithoutAnyActiveAnswerEverySpaceReadsInactive() {
        let displays = [display(spaces: [8, 9], current: nil)]
        XCTAssertEqual(PrivateWindowServerAPI.inactiveSpaceIDs(displays: displays, activeSpaceID: nil), [8, 9])
    }

    /// The production path bridges an `NSDictionary` from `SLSCopyManagedDisplaySpaces`, so the ids
    /// arrive as `NSNumber`. This is the cast that would silently answer "no spaces" if it were wrong.
    func testIDSpaceSurvivesTheNSNumberBridge() {
        let displays: [[String: Any]] = [
            [
                "Spaces": [["id64": NSNumber(value: UInt64(11))], ["id64": NSNumber(value: UInt64(12))]],
                "Current Space": ["id64": NSNumber(value: UInt64(11))]
            ]
        ]
        XCTAssertEqual(PrivateWindowServerAPI.inactiveSpaceIDs(displays: displays, activeSpaceID: nil), [12])
    }

    /// A topology with no displays answers "nothing is on another Space" rather than crashing — the
    /// same shape as the private symbols being unavailable.
    func testNoDisplaysAnswersNoInactiveSpaces() {
        XCTAssertEqual(PrivateWindowServerAPI.inactiveSpaceIDs(displays: [], activeSpaceID: 3), [])
    }

    // MARK: - Helpers

    /// One display's dictionary as `SLSCopyManagedDisplaySpaces` returns it. `current` is optional so a
    /// display that arrives without `Current Space` is expressible.
    private func display(spaces: [UInt64], current: UInt64?) -> [String: Any] {
        var display: [String: Any] = ["Spaces": spaces.map { ["id64": $0] as [String: Any] }]
        if let current {
            display["Current Space"] = ["id64": current]
        }
        return display
    }

    private func doubleBytes(_ value: Double) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
    }
}
