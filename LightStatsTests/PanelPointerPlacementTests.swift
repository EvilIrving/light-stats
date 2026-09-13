import XCTest
@testable import Light_Stats

final class PanelPointerPlacementTests: XCTestCase {
    private let panelSize = CGSize(width: 360, height: 780)
    private let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    func testCentersHorizontallyAndHangsFromThePointer() {
        let mouse = CGPoint(x: 720, y: 850)
        let origin = PanelPointerPlacement.origin(size: panelSize, mouse: mouse, visibleFrame: visible)
        XCTAssertEqual(origin.x, 720 - 180, accuracy: 0.5)
        XCTAssertEqual(origin.y, 850 - 780, accuracy: 0.5)
    }

    func testClampsToTheRightEdge() {
        let mouse = CGPoint(x: 1_430, y: 850)
        let origin = PanelPointerPlacement.origin(size: panelSize, mouse: mouse, visibleFrame: visible)
        XCTAssertEqual(origin.x, visible.maxX - panelSize.width, accuracy: 0.5)
    }

    func testClampsToTheLeftEdge() {
        let mouse = CGPoint(x: 10, y: 850)
        let origin = PanelPointerPlacement.origin(size: panelSize, mouse: mouse, visibleFrame: visible)
        XCTAssertEqual(origin.x, visible.minX, accuracy: 0.5)
    }

    func testClampsWhenThePointerIsNearTheBottom() {
        let mouse = CGPoint(x: 720, y: 40)
        let origin = PanelPointerPlacement.origin(size: panelSize, mouse: mouse, visibleFrame: visible)
        XCTAssertEqual(origin.y, visible.minY, accuracy: 0.5)
    }

    func testPinsToOriginWhenThePanelIsTallerThanTheScreen() {
        let tiny = CGRect(x: 100, y: 200, width: 200, height: 300)
        let origin = PanelPointerPlacement.origin(
            size: panelSize,
            mouse: CGPoint(x: 150, y: 400),
            visibleFrame: tiny
        )
        XCTAssertEqual(origin.x, tiny.minX, accuracy: 0.5)
        XCTAssertEqual(origin.y, tiny.minY, accuracy: 0.5)
    }
}
