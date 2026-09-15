//
//  AppDelegate+WindowMenu.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import AppKit

/// Holds a resolved window so it can ride on an `NSMenuItem`.
private final class ListedWindowBox: NSObject {
    let window: WindowPreviewItem
    init(_ window: WindowPreviewItem) { self.window = window }
}

/// Holds a visibility command so it can ride on an `NSMenuItem`.
private final class VisibilityCommandBox: NSObject {
    let command: WindowVisibilityCommand
    init(_ command: WindowVisibilityCommand) { self.command = command }
}

/// Holds a snap target so a layout segment can ride on an `NSMenuItem`.
private final class SnapTargetBox: NSObject {
    let target: SnapTarget
    init(_ target: SnapTarget) { self.target = target }
}

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

    /// 配置变化后重建菜单：布局、快捷键、悬浮岛都属于菜单要反映的状态。
    func rebuildWindowControlsMenu() {
        windowControlsStatusItem?.menu = makeWindowControlsMenu()
    }

    private func makeWindowControlsMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(windowListMenuItem())
        menu.addItem(.separator())

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
        addWindowMenuItem("window.action.maximize".localized, action: .maximize, key: "\r", to: menu)
        addWindowMenuItem("window.action.center".localized, action: .center, key: "c", to: menu)
        addWindowMenuItem("window.action.restore".localized, action: .restore, to: menu)
        addWindowMenuItem("window.action.minimize".localized, action: .minimize, to: menu)
        menu.addItem(.separator())
        addWindowMenuItem("window.action.previousDisplay".localized, action: .previousDisplay, to: menu)
        addWindowMenuItem("window.action.nextDisplay".localized, action: .nextDisplay, to: menu)

        menu.addItem(.separator())
        for command in WindowVisibilityCommand.allCases {
            addVisibilityMenuItem(command, to: menu)
        }

        if let layouts = layoutMenu() {
            menu.addItem(.separator())
            menu.addItem(layouts)
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "window.menu.openSettings".localized,
            action: #selector(openWindowManagementSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        return menu
    }

    // MARK: - Window list

    /// The live list of the target app's windows.
    ///
    /// Built on demand from `menuNeedsUpdate`, because the list is only meaningful at the moment
    /// the user opens the menu — windows come and go constantly, and a stale list that offers a
    /// window which no longer exists is worse than no list.
    /// Stable identifier for the window-list submenu.
    ///
    /// An `NSMenu`'s own title is not shown for a submenu, so it is used as an identity instead of
    /// comparing a localized string — which would break the moment the user changed language.
    private static var windowListMenuIdentifier: String { "LightStatsWindowListMenu" }

    private func windowListMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "window.menu.windows".localized, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: Self.windowListMenuIdentifier)
        submenu.delegate = self
        item.submenu = submenu
        item.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == Self.windowListMenuIdentifier else { return }
        menu.removeAllItems()

        guard let processID = targetApplicationPID() else {
            menu.addItem(disabledItem("window.menu.noApp".localized))
            return
        }
        let configuration = settings.windowSnap
        let windows = WindowListService.windows(
            forApplication: processID,
            userExclusions: configuration.exclusionSet,
            honorsRestrictedList: configuration.honorsRestrictedApps
        )

        guard !windows.isEmpty else {
            menu.addItem(disabledItem("window.menu.noWindows".localized))
            return
        }

        for window in windows {
            let title = window.isMinimized
                ? "window.menu.minimizedTitle".localized(window.title)
                : window.title
            let item = NSMenuItem(title: title, action: #selector(focusListedWindow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ListedWindowBox(window)
            item.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)

            let actions = NSMenu(title: window.title)
            actions.addItem(subItem(
                "window.menu.bringToFront".localized,
                action: #selector(focusListedWindow(_:)),
                window: window
            ))
            actions.addItem(subItem(
                window.isMinimized ? "window.menu.deminimize".localized : "window.menu.minimize".localized,
                action: #selector(toggleListedWindowMinimized(_:)),
                window: window
            ))
            actions.addItem(subItem(
                "window.menu.close".localized,
                action: #selector(closeListedWindow(_:)),
                window: window
            ))
            item.submenu = actions
            menu.addItem(item)
        }
    }

    private func subItem(_ title: String, action: Selector, window: WindowPreviewItem) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = ListedWindowBox(window)
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Layouts

    /// One submenu per layout, each listing its tiles.
    ///
    /// This is what makes a user-built layout reachable without a shortcut: the island needs a drag
    /// to the top edge, and the shortcuts need a recording, but the menu is always there.
    private func layoutMenu() -> NSMenuItem? {
        let layouts = settings.windowSnap.allLayouts.filter(\.isUsable)
        guard !layouts.isEmpty else { return nil }

        let item = NSMenuItem(title: "window.menu.layouts".localized, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
        let submenu = NSMenu(title: "window.menu.layouts".localized)

        for layout in layouts {
            let layoutItem = NSMenuItem(
                title: SnapIslandText.title(for: layout),
                action: nil,
                keyEquivalent: ""
            )
            let segments = NSMenu(title: layout.title)
            for segment in layout.segments {
                let segmentItem = NSMenuItem(
                    title: SnapIslandText.title(for: segment, in: layout),
                    action: #selector(performLayoutMenuAction(_:)),
                    keyEquivalent: ""
                )
                segmentItem.target = self
                segmentItem.representedObject = SnapTargetBox(.region(segment.rect))
                segments.addItem(segmentItem)
            }
            layoutItem.submenu = segments
            submenu.addItem(layoutItem)
        }

        item.submenu = submenu
        return item
    }

    // MARK: - Window action items

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

    private func addVisibilityMenuItem(_ command: WindowVisibilityCommand, to menu: NSMenu) {
        let item = NSMenuItem(
            title: command.titleKey.localized,
            action: #selector(performVisibilityMenuAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = VisibilityCommandBox(command)
        menu.addItem(item)
    }

    @objc private func performVisibilityMenuAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? VisibilityCommandBox else { return }
        windowSnappingService.perform(.visibility(box.command))
    }

    @objc private func performWindowMenuAction(_ sender: NSMenuItem) {
        guard let action = action(for: sender.tag), let processID = targetApplicationPID() else { return }
        windowSnappingService.perform(action, forApplication: processID)
    }

    @objc private func performLayoutMenuAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? SnapTargetBox,
              let processID = targetApplicationPID() else { return }
        windowSnappingService.perform(box.target, forApplication: processID)
    }

    @objc private func focusListedWindow(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ListedWindowBox else { return }
        _ = WindowListService.reveal(box.window)
        lastExternalApplicationPID = box.window.processID
    }

    @objc private func toggleListedWindowMinimized(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ListedWindowBox else { return }
        if box.window.isMinimized {
            _ = WindowListService.deminimize(box.window)
        } else {
            _ = WindowListService.minimize(box.window)
        }
    }

    @objc private func closeListedWindow(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ListedWindowBox else { return }
        _ = WindowListService.close(box.window)
    }

    @objc private func openWindowManagementSettings(_ sender: NSMenuItem) {
        // Status-item menus are opened by an app that is not active; the Settings scene will not
        // come forward otherwise.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(performWindowMenuAction(_:)):
            guard let action = action(for: menuItem.tag), let processID = targetApplicationPID() else { return false }
            return windowSnappingService.canPerform(action, forApplication: processID)
        case #selector(performVisibilityMenuAction(_:)):
            guard let box = menuItem.representedObject as? VisibilityCommandBox else { return false }
            return windowSnappingService.canPerform(.visibility(box.command))
        case #selector(performLayoutMenuAction(_:)):
            guard let box = menuItem.representedObject as? SnapTargetBox,
                  let processID = targetApplicationPID() else { return false }
            return windowSnappingService.canPerform(box.target, forApplication: processID)
        case #selector(focusListedWindow(_:)), #selector(toggleListedWindowMinimized(_:)), #selector(closeListedWindow(_:)):
            return menuItem.representedObject is ListedWindowBox
        default:
            return true
        }
    }

    // MARK: - Target app

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
