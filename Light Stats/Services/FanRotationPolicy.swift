//
//  FanRotationPolicy.swift
//  Light Stats
//

import Foundation

/// 转速 → 视觉角速度的唯一约定，状态栏图层与弹窗风扇共用。
///
/// 过去这套映射在两处各写了一份（`FanAnimationLayer` 与 `SpinningFanIcon`），
/// 弹窗那份还挂在逐帧 `TimelineView` 上，面板关闭后仍继续驱动整棵视图树重绘。
/// 现在数值只留在这里，旋转由 Core Animation 合成侧完成。
enum FanRotationPolicy {

    /// 视觉封顶：最快每秒 3 圈，避免高转速时「转的飞起」糊成一团。
    static let maxRevolutionsPerSecond: Double = 3

    /// 达到该转速即封顶（典型笔记本满速约 5000–6000 RPM）。
    static let revolutionsPerSecondCapRPM: Double = 5_000

    /// 角速度（圈/秒）。转速未知、为 0 或为负 → 静止。
    static func revolutionsPerSecond(rpm: Int?) -> Double {
        guard let rpm, rpm > 0 else { return 0 }
        return min(Double(rpm) / revolutionsPerSecondCapRPM, 1) * maxRevolutionsPerSecond
    }
}
