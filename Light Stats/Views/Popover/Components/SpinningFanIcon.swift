//
//  SpinningFanIcon.swift
//  Light Stats
//
//  Created on 2026/06/23.
//

import SwiftUI

/// 风扇图标：按当前转速持续旋转。转速越高转得越快，但封顶到 `maxRevPerSecond`，
/// 避免高转速时「转的飞起」糊成一团。转速为 0 / 未知时静止。
///
/// 用 `TimelineView(.animation)` 逐帧累积角度（而非 repeatForever 动画），
/// 这样转速随 RPM 变化时平滑过渡、无跳变；面板隐藏时 timeline 自动停摆，不耗电。
struct SpinningFanIcon: View {
    let rpm: Int?

    /// 视觉封顶：最快每秒 3 圈。
    private let maxRevPerSecond: Double = 3.0
    /// 达到该转速即封顶（典型笔记本满速约 5000–6000 RPM）。
    private let rpmAtMaxSpeed: Double = 5000

    @State private var angle: Double = 0
    @State private var lastDate: Date = .now

    var body: some View {
        if degreesPerSecond > 0 {
            TimelineView(.animation) { context in
                fanImage
                    .rotationEffect(.degrees(angle))
                    .onChange(of: context.date) { _, now in
                        advance(to: now)
                    }
            }
            .onAppear { lastDate = .now }
        } else {
            fanImage
        }
    }

    private var fanImage: some View {
        Image(systemName: "fanblades.fill")
    }

    /// 当前角速度（度/秒）：RPM 线性映射并封顶。
    private var degreesPerSecond: Double {
        guard let rpm, rpm > 0 else { return 0 }
        let revPerSec = min(Double(rpm) / rpmAtMaxSpeed, 1.0) * maxRevPerSecond
        return revPerSec * 360.0
    }

    /// 按帧间隔累积角度。跳过异常间隔（面板重新显示等）避免突跳。
    private func advance(to now: Date) {
        let dt = now.timeIntervalSince(lastDate)
        lastDate = now
        guard dt > 0, dt < 1 else { return }
        angle = (angle + degreesPerSecond * dt).truncatingRemainder(dividingBy: 360)
    }
}
