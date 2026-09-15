//
//  SceneAnimationPolicyTests.swift
//  Light Stats Tests
//
//  Regression net for the rule that a hidden panel/window stops per-frame scene
//  animation. The bug this pins: the popover was closed with `orderOut` while the
//  scene timeline kept ticking, re-rendering the whole view tree every frame.
//

import XCTest
@testable import Light_Stats

final class SceneAnimationPolicyTests: XCTestCase {

    func testInvisibleHostPausesEvenWithFullLightFlow() {
        XCTAssertTrue(
            SceneAnimationPolicy.isPaused(lightFlow: 1, pauseThreshold: 0.02, isVisible: false),
            "面板收起后场景时间线必须停摆，不能再按帧重绘"
        )
    }

    func testVisibleHostStaysPausedBelowThreshold() {
        XCTAssertTrue(
            SceneAnimationPolicy.isPaused(lightFlow: 0.01, pauseThreshold: 0.02, isVisible: true)
        )
    }

    func testVisibleHostRunsAtOrAboveThreshold() {
        XCTAssertFalse(
            SceneAnimationPolicy.isPaused(lightFlow: 0.02, pauseThreshold: 0.02, isVisible: true),
            "亮度正好等于阈值时按约定应运行（与场景 phase() 的 >= 语义一致）"
        )
        XCTAssertFalse(
            SceneAnimationPolicy.isPaused(lightFlow: 0.2, pauseThreshold: 0.02, isVisible: true),
            "noir 默认亮度 0.2 高于阈值 0.02，可见时必须动"
        )
    }
}
