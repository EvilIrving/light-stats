//
//  WindowSnappingServiceTests.swift
//  Light Stats Tests
//
//  Drives the engine's own placement path against a real window.
//
//  Every step here was a reported failure once: the frame write had to actually land (not just
//  return success), and it had to land on the frame the engine computed for the screen the window
//  is on. Accessibility access to our own process needs no permission, so this runs in CI too.
//

import AppKit
import ApplicationServices
import XCTest
@testable import Light_Stats

@MainActor
final class WindowSnappingServiceTests: XCTestCase {

    private var window: NSWindow?

    override func tearDown() {
        window?.orderOut(nil)
        window = nil
        super.tearDown()
    }

    func testLocalPlacementMovesARealWindowOntoTheComputedFrame() throws {
        let service = WindowSnappingService()
        let element = try makeKeyWindowElement()

        try assertPlacement(.leftHalf, service: service, element: element)
        try assertPlacement(.rightHalf, service: service, element: element)
        try assertPlacement(.topLeft, service: service, element: element)
        try assertPlacement(.bottomRight, service: service, element: element)
        try assertPlacement(.leftThird, service: service, element: element)
    }

    func testMaximizeFillsTheVisibleAreaAndRestoreReturns() throws {
        let service = WindowSnappingService()
        let element = try makeKeyWindowElement()
        let original = try XCTUnwrap(service.frame(of: element))

        let maximized = try XCTUnwrap(service.targetFrame(for: .maximize, on: element))
        XCTAssertTrue(service.placeLocally(.maximize, on: element).succeeded)
        let achieved = try XCTUnwrap(service.frame(of: element))
        assertApproximatelyEqual(achieved, maximized, "maximize")

        XCTAssertTrue(service.placeLocally(.restore, on: element).succeeded)
        let restored = try XCTUnwrap(service.frame(of: element))
        assertApproximatelyEqual(restored, original, "restore")
    }

    /// A window that is already in the requested position is a successful no-op, not a refusal: the
    /// menu item stays enabled and pressing it again changes nothing.
    func testPlacingTwiceIsIdempotent() throws {
        let service = WindowSnappingService()
        let element = try makeKeyWindowElement()

        XCTAssertTrue(service.placeLocally(.leftHalf, on: element).succeeded)
        let first = try XCTUnwrap(service.frame(of: element))
        XCTAssertTrue(service.placeLocally(.leftHalf, on: element).succeeded)
        assertApproximatelyEqual(try XCTUnwrap(service.frame(of: element)), first, "second placement")
    }

    // MARK: - Helpers

    private func assertPlacement(
        _ action: WindowSnapAction,
        service: WindowSnappingService,
        element: AXUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let target = try XCTUnwrap(service.targetFrame(for: action, on: element), "\(action)", file: file, line: line)
        let outcome = service.placeLocally(action, on: element)
        XCTAssertTrue(outcome.succeeded, "\(action) -> \(outcome)", file: file, line: line)

        let achieved = try XCTUnwrap(service.frame(of: element), "\(action)", file: file, line: line)
        assertApproximatelyEqual(achieved, target, "\(action)", file: file, line: line)
    }

    private func assertApproximatelyEqual(
        _ achieved: CGRect,
        _ target: CGRect,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Apps may clamp to the backing scale, so a couple of points of slack is expected.
        XCTAssertEqual(achieved.minX, target.minX, accuracy: 3, "\(label) x", file: file, line: line)
        XCTAssertEqual(achieved.minY, target.minY, accuracy: 3, "\(label) y", file: file, line: line)
        XCTAssertEqual(achieved.width, target.width, accuracy: 3, "\(label) width", file: file, line: line)
        XCTAssertEqual(achieved.height, target.height, accuracy: 3, "\(label) height", file: file, line: line)
    }

    private func makeKeyWindowElement() throws -> AXUIElement {
        let window = NSWindow(
            contentRect: NSRect(x: 160, y: 160, width: 720, height: 520),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WindowSnappingServiceTests"
        window.makeKeyAndOrderFront(nil)
        self.window = window
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let application = AXUIElementCreateApplication(getpid())
        let windows: [AXUIElement] = attribute(kAXWindowsAttribute, from: application) ?? []
        let titles = windows.compactMap { attribute(kAXTitleAttribute, from: $0) as String? }
        let element = windows.first { (attribute(kAXTitleAttribute, from: $0) as String?) == window.title }
        return try XCTUnwrap(element, "no AX window among \(titles)")
    }

    private func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
