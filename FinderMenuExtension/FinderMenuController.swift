import AppKit
import FinderSync
import os

/// Finder owns menu presentation; the host executes actions and records their results.
final class FinderMenuController: FIFinderSync {
    private let logger = Logger(subsystem: FinderMenuShared.extensionBundleID, category: "Extension")
    private var menuConfig = FinderMenuConfig()
    private var observingVolumes = false
    /// 菜单项 tag → 命令的寄存表。为什么按 tag、为什么不清空，见 `FinderMenuCommandRegistry`。
    private let commands = FinderMenuCommandRegistry()

    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(refreshDirectories), name: FinderMenuShared.configChanged, object: nil
        )
        refreshDirectories()
    }

    @objc private func refreshDirectories() {
        let enabled = FinderMenuShared.isEnabled()
        let workspace = NSWorkspace.shared.notificationCenter
        if enabled && !observingVolumes {
            workspace.addObserver(self, selector: #selector(refreshDirectories), name: NSWorkspace.didMountNotification, object: nil)
            workspace.addObserver(self, selector: #selector(refreshDirectories), name: NSWorkspace.didUnmountNotification, object: nil)
            observingVolumes = true
        } else if !enabled && observingVolumes {
            workspace.removeObserver(self)
            observingVolumes = false
        }
        guard enabled else {
            FIFinderSyncController.default().directoryURLs = []
            return
        }
        let config = FinderMenuShared.loadConfig()
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: .skipHiddenVolumes) ?? []
        FIFinderSyncController.default().directoryURLs = FinderMenuShared.monitoringRoots(
            home: FinderMenuShared.realHomeDirectory(), favorites: config.favoriteDirectories.map(\.path), volumes: volumes.map(\.path)
        )
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        guard FinderMenuShared.isEnabled() else { return menu }
        menuConfig = FinderMenuShared.loadConfig()
        let controller = FIFinderSyncController.default()
        let container = controller.targetedURL()?.path
        switch menuKind {
        case .contextualMenuForItems:
            let paths = (controller.selectedItemURLs() ?? []).map(\.path)
            buildItemsMenu(menu, paths: paths, container: container)
        case .contextualMenuForContainer, .contextualMenuForSidebar:
            // Finder may retain a previous selection when the user clicks blank space.
            buildContainerMenu(menu, container: container)
        default:
            break
        }
        return menu
    }

    private func buildItemsMenu(_ menu: NSMenu, paths: [String], container: String?) {
        guard !paths.isEmpty else { return }
        addItem(FinderMenuCommand(.copyPath, paths: paths, container: container), to: menu)
        addItem(FinderMenuCommand(.copyName, paths: paths, container: container), to: menu)
        addOpeningItems(menu, paths: paths, container: container)
        let directories = resolveDirectories()
        addSubmenu(.moveTo, items: directories, paths: paths, container: container, to: menu, chooseLocation: true)
        addSubmenu(.copyTo, items: directories, paths: paths, container: container, to: menu, chooseLocation: true)
        addSubmenu(.openDirectory, items: directories, paths: [], container: container, to: menu)
        addItem(FinderMenuCommand(.toggleHidden, paths: paths, container: container), to: menu)
        addItem(FinderMenuCommand(.toggleHiddenFiles), to: menu)
    }

    private func buildContainerMenu(_ menu: NSMenu, container: String?) {
        guard container != nil else { return }
        let templates = menuConfig.resolvedTemplates().map {
            (title: FinderMenuPresets.templateTitle(id: $0.id, fallback: $0.title), parameter: $0.id)
        }
        addSubmenu(.newFile, items: templates, paths: [], container: container, to: menu)
        addItem(FinderMenuCommand(.copyPath, container: container), to: menu)
        addOpeningItems(menu, paths: [], container: container)
        addSubmenu(.openDirectory, items: resolveDirectories(), paths: [], container: container, to: menu)
        addItem(FinderMenuCommand(.toggleHiddenFiles), to: menu)
    }

    private func addOpeningItems(_ menu: NSMenu, paths: [String], container: String?) {
        addItem(FinderMenuCommand(.openTerminalHere, paths: paths, container: container), to: menu)
        if menuConfig.showCmuxActions && NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.cmuxterm.app") != nil {
            addItem(FinderMenuCommand(.cmuxNewWindow, paths: paths, container: container), to: menu)
            addItem(FinderMenuCommand(.cmuxNewWorkspace, paths: paths, container: container), to: menu)
        }
        addSubmenu(.openWithApp, items: resolveApps(), paths: paths, container: container, to: menu)
    }

    private func addItem(_ command: FinderMenuCommand, title: String? = nil, to menu: NSMenu) {
        guard menuConfig.isActionEnabled(command.action) else { return }
        let item = NSMenuItem(title: title ?? command.action.localizedTitle, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.tag = commands.register(command)
        if command.action == .toggleHiddenFiles { item.state = FinderMenuShared.showsHiddenFiles ? .on : .off }
        menu.addItem(item)
    }

    private func addSubmenu(
        _ action: FinderMenuAction,
        items: [(title: String, parameter: String)],
        paths: [String], container: String?, to menu: NSMenu, chooseLocation: Bool = false
    ) {
        guard menuConfig.isActionEnabled(action), !items.isEmpty || chooseLocation else { return }
        let parent = NSMenuItem(title: action.localizedTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "")
        for entry in items {
            addItem(FinderMenuCommand(action, parameter: entry.parameter, paths: paths, container: container),
                    title: entry.title, to: submenu)
        }
        if chooseLocation {
            if !items.isEmpty { submenu.addItem(.separator()) }
            addItem(FinderMenuCommand(action, paths: paths, container: container),
                    title: FinderMenuShared.label(for: "otherLocation") ?? "Other Location…", to: submenu)
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func resolveDirectories() -> [(title: String, parameter: String)] {
        if menuConfig.favoriteDirectories.isEmpty {
            return FinderMenuPresets.favoriteDirectories().map {
                (title: FileManager.default.displayName(atPath: $0.path), parameter: $0.path)
            }
        }
        return menuConfig.favoriteDirectories.map { (title: $0.name, parameter: $0.path) }
    }

    private func resolveApps() -> [(title: String, parameter: String)] {
        let source = menuConfig.openWithApps.isEmpty
            ? FinderMenuPresets.appCandidates.map { (title: $0.name, parameter: $0.bundleID) }
            : menuConfig.openWithApps.map { (title: $0.name, parameter: $0.bundleID) }
        return source.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.parameter) != nil }
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard FinderMenuShared.isEnabled(), let command = commands.command(for: sender.tag) else { return }
        let request = FinderMenuRequest(action: command.action, paths: command.paths,
                                        container: command.container, parameter: command.parameter)
        let logger = logger
        Task { await FinderMenuIPCClient.send(request, logger: logger) }
    }
}
