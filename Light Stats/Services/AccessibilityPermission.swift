//
//  AccessibilityPermission.swift
//  Light Stats
//
//  Created on 2026/06/26.
//

import AppKit
import ApplicationServices
import OSLog

/// 辅助功能权限的统一入口。检测与跳转系统设置在此；系统引导弹窗见
/// `AccessibilityPermission.presentSettingsAlert`（Views 扩展）。
///
/// 双重隔离：`isTrusted` 是纯 syscall，标 `nonisolated` 供任意线程同步调用；
/// 跳转涉及 AppKit，标 `@MainActor`。
nonisolated enum AccessibilityPermission {

    private static let log = AppLogger(category: "AccessibilityPermission")

    /// 系统设置 → 隐私与安全性 → 辅助功能。
    static let settingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// 是否已授予辅助功能权限。`prompt` 为 true 时由系统弹出原生授权请求对话框。
    static func isTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 跳转系统设置的辅助功能页。
    @MainActor
    static func openSettings() {
        guard let url = URL(string: settingsURLString) else {
            log.error("Failed to build Accessibility settings URL")
            return
        }
        NSWorkspace.shared.open(url)
    }
}
