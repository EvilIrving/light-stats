//
//  SpinningFanIcon.swift
//  Light Stats
//
//  Created on 2026/06/23.
//

import SwiftUI

/// 风扇图标：按当前转速持续旋转。转速越高转得越快，封顶见 `FanRotationPolicy`。
/// 转速为 0 / 未知时只显示静止图标。
///
/// 旋转由 `FanIconLayerView` 在合成侧完成，不进 SwiftUI 图。之前的做法是用
/// `TimelineView(.animation)` 逐帧累积角度，每帧都会让整个弹窗视图树变脏、
/// 由 AppKit 重做整体 layout——而 `orderOut` 的窗口不会替我们暂停这类时间线，
/// 面板关掉后它照样以显示刷新率空转。可见性因此必须显式传入。
struct SpinningFanIcon: View {
    @Environment(\.theme) private var theme

    let rpm: Int?
    /// 弹窗面板是否可见；`false` 时停止旋转。
    var isPanelVisible: Bool = true

    /// 与相邻读数同一字号，避免行内基线跳动。
    private let pointSize: CGFloat = 11

    var body: some View {
        FanIconLayerView(
            rpm: rpm,
            isPanelVisible: isPanelVisible,
            tintColor: theme.metricIcon,
            pointSize: pointSize
        )
        .frame(width: pointSize, height: pointSize)
        .accessibilityHidden(true)
    }
}
