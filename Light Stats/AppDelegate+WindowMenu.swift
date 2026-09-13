//
//  AppDelegate+WindowMenu.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import AppKit

/// 菜单栏窗口控制图标及其菜单。
///
/// 原生分屏作用在「用户原本所在 App」的窗口上，而打开我们自己的菜单已经抢走了前台，
/// 所以菜单项必须先解析出目标 App（`targetApplicationPID()`）再交给 `WindowSnappingService`。
extension AppDelegate {

    /// 仅当窗口管理开启时创建菜单栏图标；已存在则幂等返回。
    func ensureWindowControlsStatusItem() {
        guard windowControlsStatusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let description = "settings.windowControls".localized
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: description)
            button.image?.isTemplate = true
        }
        item.menu = makeWindowControlsMenu()
        windowControlsStatusItem = item
    }

    /// 关闭窗口管理时彻底移除图标（而非仅隐藏），不留菜单栏占位。
    func removeWindowControlsStatusItem() {
        guard let item = windowControlsStatusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        windowControlsStatusItem = nil
    }

    private func makeWindowControlsMenu() -> NSMenu {
        let menu = NSMenu()
        addWindowMenuItem("window.action.left".localized, action: .leftHalf, key: "←", to: menu)
        addWindowMenuItem("window.action.right".localized, action: .rightHalf, key: "→", to: menu)
        addWindowMenuItem("window.action.top".localized, action: .topHalf, key: "↑", to: menu)
        addWindowMenuItem("window.action.bottom".localized, action: .bottomHalf, key: "↓", to: menu)
        menu.addItem(.separator())
        addWindowMenuItem("window.action.topLeft".localized, action: .topLeft, to: menu)
        addWindowMenuItem("window.action.topRight".localized, action: .topRight, to: menu)
        addWindowMenuItem("window.action.bottomLeft".localized, action: .bottomLeft, to: menu)
        addWindowMenuItem("window.action.bottomRight".localized, action: .bottomRight, to: menu)
        menu.addItem(.separator())
        addWindowMenuItem("window.action.leftThird".localized, action: .leftThird, to: menu)
        addWindowMenuItem("window.action.leftTwoThirds".localized, action: .leftTwoThirds, to: menu)
        addWindowMenuItem("window.action.centerThird".localized, action: .centerThird, to: menu)
        addWindowMenuItem("window.action.rightTwoThirds".localized, action: .rightTwoThirds, to: menu)
        addWindowMenuItem("window.action.rightThird".localized, action: .rightThird, to: menu)
        menu.addItem(.separator())
        addWindowMenuItem(
            "window.action.previousDisplay".localized,
            action: .previousDisplay,
            to: menu
        )
        addWindowMenuItem(
            "window.action.nextDisplay".localized,
            action: .nextDisplay,
            to: menu
        )
        menu.addItem(.separator())
        addWindowMenuItem("window.action.maximize".localized, action: .maximize, key: "\r", to: menu)
        addWindowMenuItem("window.action.center".localized, action: .center, key: "c", to: menu)
        addWindowMenuItem("window.action.restore".localized, action: .restore, to: menu)
        return menu
    }

    private func addWindowMenuItem(
        _ title: String,
        action: WindowSnapAction,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.control, .option],
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: #selector(performWindowMenuAction(_:)), keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.tag = tag(for: action)
        item.image = WindowSnapIconProvider.icon(for: action)
        menu.addItem(item)
    }

    @objc private func performWindowMenuAction(_ sender: NSMenuItem) {
        guard let action = action(for: sender.tag), let processID = targetApplicationPID() else { return }
        windowSnappingService.perform(action, forApplication: processID)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performWindowMenuAction(_:)) else { return true }
        guard let action = action(for: menuItem.tag), let processID = targetApplicationPID() else { return false }
        return windowSnappingService.canPerform(action, forApplication: processID)
    }

    /// 菜单项该作用在哪个 App 上：优先用「打开菜单前的前台 App」，记录缺失或已退出时退回当前前台 App。
    private func targetApplicationPID() -> pid_t? {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        if let recorded = lastExternalApplicationPID,
           recorded != selfPID,
           NSRunningApplication(processIdentifier: recorded) != nil {
            return recorded
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return frontmost == selfPID ? nil : frontmost
    }

    private func tag(for action: WindowSnapAction) -> Int {
        Self.windowMenuActions.first { $0.action == action }?.tag ?? 0
    }

    private func action(for tag: Int) -> WindowSnapAction? {
        Self.windowMenuActions.first { $0.tag == tag }?.action
    }
}
