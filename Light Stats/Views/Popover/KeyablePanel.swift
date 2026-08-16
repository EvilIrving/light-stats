//
//  KeyablePanel.swift
//  Light Stats
//

import AppKit

/// 无标题栏的浮动面板默认 `canBecomeKey` 返回 false，导致 `makeKeyAndOrderFront`
/// 无法设为 key window（控制台报 makeKeyWindow 警告），且配合 `hidesOnDeactivate`
/// 会在激活时立刻被隐藏。重写这两个属性以允许面板成为 key/main window。
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// 面板失去 key 焦点（点击外部 / 切换到别的菜单栏图标）时回调。
    /// 复刻 NSPopover .transient 的自动关闭行为，参考 Maccy 的 FloatingPanel。
    var onResignKey: (() -> Void)?

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
