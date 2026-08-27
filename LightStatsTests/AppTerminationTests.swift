import AppKit
import XCTest
@testable import Light_Stats

@MainActor
final class AppTerminationTests: XCTestCase {
    func testTerminationIsImmediate() {
        let delegate = AppDelegate()
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateNow)
    }
}
