//
//  FanAnimationLayerTests.swift
//  Light Stats Tests
//
//  Regression net for the fan layer's lifecycle: a hidden host must not keep a
//  rotation running behind an offscreen window. The rpm → speed curve itself is
//  pinned in `FanRotationPolicyTests`.
//

import XCTest
@testable import Light_Stats

@MainActor
final class FanAnimationLayerTests: XCTestCase {

    func testVisibleHostRotatesAtPolicySpeed() {
        let layer = FanAnimationLayer()
        layer.update(rpm: 3_000, visible: true, contentsScale: 2, tintColor: .black)

        XCTAssertFalse(layer.isHidden, "可见时风扇图标必须显示")
        XCTAssertEqual(
            layer.sublayers?.first?.speed ?? 0,
            1.8,
            accuracy: 0.0001,
            "3000 RPM 应达到策略给定的角速度"
        )
    }

    func testHiddenHostStopsRotatingAndHidesIcon() {
        let layer = FanAnimationLayer()
        layer.update(rpm: 3_000, visible: true, contentsScale: 2, tintColor: .black)
        layer.update(rpm: 3_000, visible: false, contentsScale: 2, tintColor: .black)

        XCTAssertTrue(layer.isHidden, "面板收起后图标应隐藏")
        XCTAssertEqual(
            layer.sublayers?.first?.speed ?? 0,
            0,
            accuracy: 0.0001,
            "面板收起后不得继续空转"
        )
    }

    func testZeroRPMShowsStaticIcon() {
        let layer = FanAnimationLayer()
        layer.update(rpm: 0, visible: true, contentsScale: 2, tintColor: .black)

        XCTAssertFalse(layer.isHidden, "转速为 0 时仍要显示静止的风扇图标")
        XCTAssertEqual(layer.sublayers?.first?.speed ?? 0, 0, accuracy: 0.0001)
    }

    func testSpeedMappingIsDelegatedToPolicy() {
        XCTAssertEqual(
            FanAnimationLayer.visualSpeed(for: 2_500),
            FanRotationPolicy.revolutionsPerSecond(rpm: 2_500)
        )
    }
}
