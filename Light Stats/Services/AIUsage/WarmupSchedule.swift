//
//  WarmupSchedule.swift
//  Light Stats
//
//  Created on 2026/06/28.
//

import Foundation

/// Pure scheduling policy for usage-window warmup. No I/O, no state — the manager
/// owns the loop, this owns the "what to do next" decision so it can be unit-tested
/// against every knee. Mirrors the empirical P0 finding: a mid-window send does not
/// move the reset, so warmup is only useful just *after* a window expires.
enum WarmupSchedule {

    /// 窗口过期后多久补发：让新窗口的起点落在过期后一点点，确保 anchor 的是新窗口。
    static let anchorDelay: TimeInterval = 60

    enum Decision: Equatable {
        case waitForWindow            // 还不知道窗口 reset，等监控拉到数据
        case sleep(TimeInterval)      // 未到补发点，睡这么久（已被上限夹取）
        case sendNow                  // 已过补发点且本窗口尚未 anchor → 立刻发
    }

    /// 决定下一步动作。
    /// - Parameters:
    ///   - now: 当前时刻。
    ///   - reset: 当前滚动窗口的 reset 时刻（可能略早于 `now`；`nil` 表示未知）。
    ///   - lastAnchoredReset: 上次已 anchor 的窗口 reset，用于去重——避免监控刷新延迟期间重复发送。
    ///   - cap: 单次最长睡眠。分块轮询保证系统睡眠唤醒后能尽快重新判断（墙钟自校正）。
    static func decide(now: Date,
                       reset: Date?,
                       lastAnchoredReset: Date?,
                       cap: TimeInterval = 60) -> Decision {
        guard let reset else { return .waitForWindow }
        if let last = lastAnchoredReset, last == reset { return .sleep(cap) }
        let delta = reset.addingTimeInterval(anchorDelay).timeIntervalSince(now)
        if delta <= 0 { return .sendNow }
        return .sleep(min(delta, cap))
    }
}
