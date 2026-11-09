//
//  AccessibilityPermission.swift
//  Light Stats
//
//  Created on 2026/06/26.
//

import ApplicationServices

/// 辅助功能权限的统一入口。
///
/// 只负责「有没有」这一个判定：`isTrusted` 是纯 syscall，标 `nonisolated` 供任意线程同步调用。
/// 系统设置深链与怎么引导用户过去，都归 `PermissionPane` / `PermissionGuideCenter`，
/// 免得同一个 URL 在几处各写一份。
nonisolated enum AccessibilityPermission {

    /// 是否已授予辅助功能权限。`prompt` 为 true 时由系统弹出原生授权请求对话框。
    static func isTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
