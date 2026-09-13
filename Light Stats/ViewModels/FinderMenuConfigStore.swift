//
//  FinderMenuConfigStore.swift
//  Light Stats
//
//  Finder 右键菜单可编辑配置（常用目录 / 打开方式 App）的宿主侧 ViewModel。
//  读写经 FinderMenuShared 落到 App Group 容器；扩展在下次 menu(for:) 实时读取。
//  列表为空 → 扩展沿用内置预设，所以"清空"等于"恢复默认"。
//

import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FinderMenuConfigStore: ObservableObject {

    static let shared = FinderMenuConfigStore()

    @Published private(set) var config: FinderMenuConfig
    @Published private(set) var isImportingTemplate = false
    @Published private(set) var templateError: String?

    /// 扩展在系统 pkd 里的真实状态，供设置页提示用户是否还需在系统设置中手动启用。
    @Published private(set) var extensionStatus: FinderExtensionStatus = .unknown

    init(config: FinderMenuConfig? = nil) {
        self.config = config ?? FinderMenuShared.loadConfig()
    }

    /// 将文件面板作为设置窗口的 sheet 展示，避免应用级 modal 与 SwiftUI 设置页的
    /// 外层 ScrollView 争用事件循环。设置窗口尚未可用时仍使用异步 app-modal。
    private func present(_ panel: NSOpenPanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        NotificationCenter.default.post(name: .finderMenuFilePanelWillPresent, object: nil)
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            NotificationCenter.default.post(name: .finderMenuFilePanelDidDismiss, object: nil)
            completion(response)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    /// 在后台线程查询 pluginkit，回主线程更新发布属性。设置页 onAppear 调用。
    func refreshExtensionStatus() {
        Task {
            let status = await Task.detached { FinderMenuHostService.extensionStatus() }.value
            extensionStatus = status
        }
    }

    func restartFinder() {
        Task {
            let restarted = await FinderMenuSystemService.restartFinder()
            ToastCenter.shared.show(
                message: (restarted ? "settings.finderMenu.finderRefreshing" : "findermenu.toast.visibilityFailed").localized,
                systemImage: restarted ? "arrow.clockwise" : "exclamationmark.triangle", tint: restarted ? .blue : .orange
            )
            refreshExtensionStatus()
        }
    }

    // MARK: - Directories

    /// 弹文件夹选择器，把所选目录加入常用目录（去重，按路径）。
    /// 用 `begin(completionHandler:)` 而非同步 `runModal()`——后者在 SwiftUI 按钮回调
    /// 内会阻塞主线程，与 SwiftUI 的事件循环形成死锁导致 UI 卡死。
    func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        present(panel) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let entry = FinderMenuConfig.DirectoryEntry(name: url.lastPathComponent, path: url.path)
            guard !self.config.favoriteDirectories.contains(where: { $0.path == entry.path }) else { return }
            self.config.favoriteDirectories.append(entry)
            self.persist()
        }
    }

    func removeDirectory(_ entry: FinderMenuConfig.DirectoryEntry) {
        config.favoriteDirectories.removeAll { $0.path == entry.path }
        persist()
    }

    // MARK: - Apps

    /// 弹 App 选择器（默认定位 /Applications），读取 bundle id 加入打开方式列表。
    /// 用 `begin(completionHandler:)` 而非同步 `runModal()`——后者在 SwiftUI 按钮回调
    /// 内会阻塞主线程，与 SwiftUI 的事件循环形成死锁导致 UI 卡死。
    func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        present(panel) { [weak self] response in
            guard let self, response == .OK, let url = panel.url,
                  let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            let name = url.deletingPathExtension().lastPathComponent
            let entry = FinderMenuConfig.AppEntry(name: name, bundleID: bundleID)
            guard !self.config.openWithApps.contains(where: { $0.bundleID == bundleID }) else { return }
            self.config.openWithApps.append(entry)
            self.persist()
        }
    }

    func removeApp(_ entry: FinderMenuConfig.AppEntry) {
        config.openWithApps.removeAll { $0.bundleID == entry.bundleID }
        persist()
    }

    // MARK: - Terminal / Integrations

    func setTerminalID(_ id: String) {
        config.terminalID = FinderMenuPresets.normalizeTerminalID(id)
        persist()
    }

    func setShowCmuxActions(_ enabled: Bool) {
        config.showCmuxActions = enabled
        persist()
    }

    // MARK: - Templates

    func isTerminalInstalled(_ terminal: FinderMenuPresets.TerminalPreset) -> Bool {
        guard let bundleID = terminal.bundleID else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    func setAction(_ action: FinderMenuAction, enabled: Bool) {
        config.hiddenActionIDs.removeAll { $0 == action.rawValue }
        if !enabled { config.hiddenActionIDs.append(action.rawValue) }
        persist()
    }

    /// Store a private copy so moving or deleting the original never breaks the template.
    func addTemplate() {
        guard !isImportingTemplate else { return }
        templateError = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "settings.finderMenu.customTemplatesHint".localized
        present(panel) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.isImportingTemplate = true
            Task {
                defer { self.isImportingTemplate = false }
                do {
                    let entry = try await FinderMenuFileService.shared.importTemplate(from: url)
                    self.config.templates.append(entry)
                    self.persist()
                } catch {
                    self.templateError = "settings.finderMenu.templateImportFailed".localized
                    DiagnosticLogService.record(level: .error, category: "finderMenu", action: "templateImportFailed",
                                                fields: ["reason": String(describing: type(of: error))])
                }
            }
        }
    }

    func removeTemplate(_ entry: FinderMenuConfig.TemplateEntry) {
        templateError = nil
        Task {
            do {
                try await FinderMenuFileService.shared.removeTemplate(entry)
                config.templates.removeAll { $0.id == entry.id }
                persist()
            } catch {
                templateError = "settings.finderMenu.templateRemoveFailed".localized
            }
        }
    }

    // MARK: - Preset template visibility

    /// 当前生效的勾选集合（`nil` → 默认子集）。
    private var effectiveEnabledTemplateIDs: [String] {
        config.enabledTemplateIDs ?? FinderMenuPresets.defaultEnabledTemplateIDs
    }

    func isPresetTemplateEnabled(_ id: String) -> Bool {
        effectiveEnabledTemplateIDs.contains(id)
    }

    /// 勾选/取消某个内置类型。首次切换会把默认子集固化成显式列表，
    /// 之后即使关掉某个默认项也会持久保留（空数组＝一个内置类型都不显示）。
    func setPresetTemplate(_ id: String, enabled: Bool) {
        var ids = effectiveEnabledTemplateIDs
        if enabled {
            guard !ids.contains(id) else { return }
            ids.append(id)
        } else {
            ids.removeAll { $0 == id }
        }
        config.enabledTemplateIDs = ids
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        FinderMenuShared.saveConfig(config)
    }
}
