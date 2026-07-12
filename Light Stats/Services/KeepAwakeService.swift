//
//  KeepAwakeService.swift
//  Light Stats
//
//  Created on 2026/06/28.
//
//  阻止显示器空闲息屏（等价 `caffeinate -d`），用 IOPMAssertion 电源断言实现。
//  opt-in、默认关闭：start() 持有一个 PreventUserIdleDisplaySleep 断言，stop() 释放。
//  不自动超时——持续到用户关闭开关或退出 App（断言随进程结束由系统回收，stop 也会显式释放）。
//

import Foundation
import IOKit.pwr_mgt
import os

/// 保持唤醒（阻止息屏）的生命周期服务。Shape C：显式 start()/stop()，由 AppDelegate
/// 在 `keepAwakeEnabled` 开关变化时驱动。无 CGEventTap、无辅助功能权限。
@MainActor
final class KeepAwakeService {

    static let shared = KeepAwakeService()

    private(set) var isRunning = false
    private var assertionID = IOPMAssertionID(0)
    private let log = AppLogger(category: "KeepAwake")

    private init() {}

    /// 持有断言阻止显示器息屏。已在运行则幂等返回 true；创建失败返回 false。
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Light Stats keep awake" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            log.error("keep-awake assertion failed: \(result)")
            return false
        }
        assertionID = id
        isRunning = true
        log.info("keep-awake on")
        return true
    }

    /// 释放断言，显示器恢复正常息屏。未运行则无操作。
    func stop() {
        guard isRunning else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        isRunning = false
        log.info("keep-awake off")
    }
}
