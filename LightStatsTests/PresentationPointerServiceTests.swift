//
//  PresentationPointerServiceTests.swift
//  LightStatsTests
//
//  Exercises the real click-through overlay window lifecycle.
//

import CoreGraphics
import XCTest
@testable import Light_Stats

@MainActor
final class PresentationPointerServiceTests: XCTestCase {

    func testStartAndStopManageOverlayWindow() {
        let service = PresentationPointerService()
        XCTAssertFalse(service.isRunning)

        service.start()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(service.isRunning)
        XCTAssertEqual(presentationPointerWindowCount(), 1)

        service.stop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(presentationPointerWindowCount(), 0)
    }

    private func presentationPointerWindowCount() -> Int {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let processID = Int(ProcessInfo.processInfo.processIdentifier)
        return windows.filter { window in
            guard window[kCGWindowOwnerPID as String] as? Int == processID,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Int,
                  let height = bounds["Height"] as? Int else { return false }
            return width == 112 && height == 112
        }.count
    }
}
