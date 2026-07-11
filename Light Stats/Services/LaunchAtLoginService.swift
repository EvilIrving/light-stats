//
//  LaunchAtLoginService.swift
//  Light Stats
//
//  Created on 2026/06/26.
//

import Foundation
import ServiceManagement
import os

/// 开机启动：包装 `SMAppService.mainApp`（macOS 13+）。系统本身是唯一真相源，
/// 不落 UserDefaults——以登录项实际注册状态为准。纯同步调用，标 `nonisolated`。
nonisolated enum LaunchAtLoginService {

    private static let log = AppLogger(subsystem: "com.lightstats", category: "LaunchAtLogin")

    /// 当前是否已注册为登录项。
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 注册或注销登录项。失败时记录日志并向上抛出，由调用方决定如何回滚 UI 状态。
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            log.info("Registered launch-at-login")
        } else {
            try SMAppService.mainApp.unregister()
            log.info("Unregistered launch-at-login")
        }
    }
}
