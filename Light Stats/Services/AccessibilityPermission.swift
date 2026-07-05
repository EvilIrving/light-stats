//
//  AccessibilityPermission.swift
//  Light Stats
//
//  Created on 2026/06/26.
//

import AppKit
import ApplicationServices
import OSLog

/// 辅助功能权限的统一入口。把原本散落在 `KeyboardLockService` / `WindowSnappingService` /
/// `ScrollDirectionService` 三处重复的 `AXIsProcessTrustedWithOptions` 检测，以及
/// `AppDelegate` / `CleaningModeViewModel` 两处重复的「NSAlert 引导 + 跳转系统设置」
/// 收敛到一处，保证权限检测路径与提示 UI 完全一致。
///
/// 双重隔离：`isTrusted` 是纯 syscall，标 `nonisolated` 供任意线程同步调用；
/// 弹窗与跳转涉及 AppKit，标 `@MainActor`。
nonisolated enum AccessibilityPermission {

    private static let log = Logger(subsystem: "com.lightstats", category: "AccessibilityPermission")

    /// 系统设置 → 隐私与安全性 → 辅助功能。
    private static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// 是否已授予辅助功能权限。`prompt` 为 true 时由系统弹出原生授权请求对话框。
    static func isTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 统一的权限引导弹窗：固定「打开设置 / 稍后」两个按钮，确认则跳转辅助功能设置页。
    /// 用 `beginSheetModal` 而非同步 `runModal()`——后者在 SwiftUI 上下文中可能
    /// 与事件循环形成死锁。无可用 window 时回退到 `runModal()`。
    @MainActor
    static func presentSettingsAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "cleaning.permission.openSettings".localized)
        alert.addButton(withTitle: "update.action.later".localized)
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    openSettings()
                }
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                openSettings()
            }
        }
    }

    /// 跳转系统设置的辅助功能页。
    @MainActor
    static func openSettings() {
        guard let url = URL(string: settingsURL) else {
            log.error("Failed to build Accessibility settings URL")
            return
        }
        NSWorkspace.shared.open(url)
    }
}
