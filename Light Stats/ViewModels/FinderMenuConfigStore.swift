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
import UniformTypeIdentifiers

@MainActor
final class FinderMenuConfigStore: ObservableObject {

    static let shared = FinderMenuConfigStore()

    @Published private(set) var config: FinderMenuConfig

    private init() {
        config = FinderMenuShared.loadConfig()
    }

    // MARK: - Directories

    /// 弹文件夹选择器，把所选目录加入常用目录（去重，按路径）。
    func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let entry = FinderMenuConfig.DirectoryEntry(name: url.lastPathComponent, path: url.path)
        guard !config.favoriteDirectories.contains(where: { $0.path == entry.path }) else { return }
        config.favoriteDirectories.append(entry)
        persist()
    }

    func removeDirectory(_ entry: FinderMenuConfig.DirectoryEntry) {
        config.favoriteDirectories.removeAll { $0.path == entry.path }
        persist()
    }

    // MARK: - Apps

    /// 弹 App 选择器（默认定位 /Applications），读取 bundle id 加入打开方式列表。
    func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }

        let name = url.deletingPathExtension().lastPathComponent
        let entry = FinderMenuConfig.AppEntry(name: name, bundleID: bundleID)
        guard !config.openWithApps.contains(where: { $0.bundleID == bundleID }) else { return }
        config.openWithApps.append(entry)
        persist()
    }

    func removeApp(_ entry: FinderMenuConfig.AppEntry) {
        config.openWithApps.removeAll { $0.bundleID == entry.bundleID }
        persist()
    }

    // MARK: - Templates

    /// 选一个文本文件作为「新建文件」模板：其内容即模板内容，扩展名沿用，文件名作标题。
    /// 仅支持可按 UTF-8 读取的文本文件；二进制模板（Word/Excel 等）暂不支持。
    func addTemplate() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let entry = FinderMenuConfig.TemplateEntry(
            id: UUID().uuidString,
            title: url.lastPathComponent,
            fileExtension: url.pathExtension,
            content: content
        )
        config.templates.append(entry)
        persist()
    }

    func removeTemplate(_ entry: FinderMenuConfig.TemplateEntry) {
        config.templates.removeAll { $0.id == entry.id }
        persist()
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
