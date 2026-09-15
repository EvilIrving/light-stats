//
//  SceneAnimationPolicy.swift
//  Light Stats
//

import Foundation

/// 动态主题场景的逐帧时间线是否应该运行。
///
/// 弹窗面板是用 `panel.orderOut(nil)` 隐藏的普通 `NSPanel`：窗口虽然不再合成，
/// hosting view 仍留在窗口里，SwiftUI 不会替我们暂停 `TimelineView`。实测面板关闭后
/// 场景与风扇仍在按帧重绘整棵视图树（主线程 36% 卡在 `NSWindow layoutIfNeeded`），
/// 所以可见性必须由调用方显式传入。
///
/// 阈值语义与场景自身的 `phase()` / `motionOffset()` 保持一致：`lightFlow >= threshold`
/// 才动，低于阈值只画静态首帧。
enum SceneAnimationPolicy {

    /// 时间线是否暂停。不可见优先于亮度：窗口收起来就没有「亮度够不够」的问题。
    static func isPaused(lightFlow: Double, pauseThreshold: Double, isVisible: Bool) -> Bool {
        guard isVisible else { return true }
        return lightFlow < pauseThreshold
    }
}
