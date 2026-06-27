//
//  FinderMenuController.swift
//  FinderMenuExtension
//
//  FinderSync 扩展主体：仅监控用户主目录，按总开关在 Finder 右键菜单注入 Light Stats
//  动作。纯剪贴板动作在本进程内完成；需要文件操作的动作通过 CFMessagePort 委派给
//  非沙盒宿主执行（见 FinderMenuIPCClient / FinderMenuHostService）。
//

import AppKit
import FinderSync
import os

final class FinderMenuController: FIFinderSync {

    private let logger = Logger(subsystem: "com.lightstats.findermenu", category: "Extension")

    override init() {
        super.init()
        // 决策：仅注册用户主目录，覆盖约 95% 场景，规避「一目录一扩展 / 嵌套」限制。
        // 关键：扩展是沙盒进程，NSHomeDirectory() 返回沙盒容器路径而非真实主目录，
        // 必须用 FinderMenuShared.realHomeDirectory()（getpwuid）绕过沙盒重定向。
        let home = URL(fileURLWithPath: FinderMenuShared.realHomeDirectory())
        FIFinderSyncController.default().directoryURLs = [home]
        logger.info("FinderMenu extension initialised, monitoring \(home.path, privacy: .public)")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        // 总开关关闭时不出任何菜单项——干净安装上的零侵扰契约。
        guard FinderMenuShared.isEnabled() else { return menu }

        switch menuKind {
        case .contextualMenuForItems:
            buildItemsMenu(menu)
        case .contextualMenuForContainer, .contextualMenuForSidebar:
            buildContainerMenu(menu)
        default:
            break
        }
        return menu
    }

    // MARK: - Menu builders

    /// 选中文件 / 文件夹时的菜单。
    private func buildItemsMenu(_ menu: NSMenu) {
        addItem(FinderMenuCommand(.copyPath), title: FinderMenuAction.copyPath.localizedTitle, to: menu)
        addItem(FinderMenuCommand(.copyName), title: FinderMenuAction.copyName.localizedTitle, to: menu)
        addItem(FinderMenuCommand(.openTerminalHere), title: FinderMenuAction.openTerminalHere.localizedTitle, to: menu)

        let config = FinderMenuShared.loadConfig()
        let appItems = resolveApps(config).map { (title: $0.name, parameter: $0.bundleID) }
        addSubmenu(.openWithApp, items: appItems, to: menu)

        let dirItems = resolveDirectories(config).map { (title: $0.name, parameter: $0.path) }
        addSubmenu(.moveTo, items: dirItems, to: menu)
        addSubmenu(.copyTo, items: dirItems, to: menu)

        addItem(FinderMenuCommand(.toggleHidden), title: FinderMenuAction.toggleHidden.localizedTitle, to: menu)
    }

    /// 右键空白处 / 侧边栏目录时的菜单。
    private func buildContainerMenu(_ menu: NSMenu) {
        let templateItems = FinderMenuShared.loadConfig().resolvedTemplates().map { (title: $0.title, parameter: $0.id) }
        addSubmenu(.newFile, items: templateItems, to: menu)
        addItem(FinderMenuCommand(.openTerminalHere), title: FinderMenuAction.openTerminalHere.localizedTitle, to: menu)
    }

    // MARK: - Item helpers

    private func addItem(_ command: FinderMenuCommand, title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command
        menu.addItem(item)
    }

    private func addSubmenu(_ action: FinderMenuAction, items: [(title: String, parameter: String)], to menu: NSMenu) {
        guard !items.isEmpty else { return }
        let parent = NSMenuItem(title: action.localizedTitle, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "")
        for entry in items {
            let item = NSMenuItem(title: entry.title, action: #selector(runAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = FinderMenuCommand(action, parameter: entry.parameter)
            sub.addItem(item)
        }
        parent.submenu = sub
        menu.addItem(parent)
    }

    /// 常用目录：用户配置非空则用配置，否则用内置预设。
    private func resolveDirectories(_ config: FinderMenuConfig) -> [(name: String, path: String)] {
        if config.favoriteDirectories.isEmpty {
            return FinderMenuPresets.favoriteDirectories().map { (name: $0.name, path: $0.path) }
        }
        return config.favoriteDirectories.map { (name: $0.name, path: $0.path) }
    }

    /// 打开方式 App：用户配置非空则用配置，否则用内置候选；统一过滤掉未安装的。
    private func resolveApps(_ config: FinderMenuConfig) -> [(name: String, bundleID: String)] {
        let source: [(name: String, bundleID: String)] = config.openWithApps.isEmpty
            ? FinderMenuPresets.appCandidates.map { (name: $0.name, bundleID: $0.bundleID) }
            : config.openWithApps.map { (name: $0.name, bundleID: $0.bundleID) }
        return source.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }
    }

    // MARK: - Action dispatch

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? FinderMenuCommand else { return }

        let controller = FIFinderSyncController.default()
        let paths = (controller.selectedItemURLs() ?? []).map(\.path)
        let container = controller.targetedURL()?.path

        if command.action.requiresHost {
            let request = FinderMenuRequest(
                action: command.action, paths: paths, container: container, parameter: command.parameter
            )
            FinderMenuIPCClient.send(request, logger: logger)
        } else {
            handleLocally(command.action, paths: paths)
        }
    }

    /// 扩展内直接处理的剪贴板动作（无文件 IO，无需委派宿主）。
    private func handleLocally(_ action: FinderMenuAction, paths: [String]) {
        let text: String
        switch action {
        case .copyPath:
            text = paths.joined(separator: "\n")
        case .copyName:
            text = paths.map { ($0 as NSString).lastPathComponent }.joined(separator: "\n")
        default:
            return
        }
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
