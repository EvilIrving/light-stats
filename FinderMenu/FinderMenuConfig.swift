//
//  FinderMenuConfig.swift
//  Light Stats / FinderMenuExtension
//
//  用户可编辑的 Finder 菜单配置，以 JSON 存入 App Group 容器，宿主写、扩展读。
//  空列表表示「沿用内置预设」——这样干净安装即有合理默认，用户编辑后才覆盖。
//
//  自定义 init(from:) 用 decodeIfPresent：新增字段时旧的已存 JSON 不会解码失败，
//  缺失字段退化为空数组（= 沿用预设），向后兼容。
//

import Foundation

nonisolated struct FinderMenuConfig: Codable, Sendable {
    var favoriteDirectories: [DirectoryEntry]
    var openWithApps: [AppEntry]
    var templates: [TemplateEntry]
    /// 选中显示在「新建文件」菜单里的内置预设类型 id。
    /// `nil` = 未设置，沿用 `FinderMenuPresets.defaultEnabledTemplateIDs`；
    /// 非 nil（含空数组）= 用户显式选择，空数组即「一个内置类型都不显示」。
    var enabledTemplateIDs: [String]?

    init(favoriteDirectories: [DirectoryEntry] = [],
         openWithApps: [AppEntry] = [],
         templates: [TemplateEntry] = [],
         enabledTemplateIDs: [String]? = nil) {
        self.favoriteDirectories = favoriteDirectories
        self.openWithApps = openWithApps
        self.templates = templates
        self.enabledTemplateIDs = enabledTemplateIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoriteDirectories = try container.decodeIfPresent([DirectoryEntry].self, forKey: .favoriteDirectories) ?? []
        openWithApps = try container.decodeIfPresent([AppEntry].self, forKey: .openWithApps) ?? []
        templates = try container.decodeIfPresent([TemplateEntry].self, forKey: .templates) ?? []
        enabledTemplateIDs = try container.decodeIfPresent([String].self, forKey: .enabledTemplateIDs)
    }

    struct DirectoryEntry: Codable, Sendable, Identifiable {
        var id: String { path }
        var name: String
        var path: String
    }

    struct AppEntry: Codable, Sendable, Identifiable {
        var id: String { bundleID }
        var name: String
        var bundleID: String
    }

    struct TemplateEntry: Codable, Sendable, Identifiable {
        var id: String
        var title: String
        var fileExtension: String
        var content: String
    }

    /// 新建文件模板：勾选的内置预设（按预设顺序）+ 用户自定义模板。
    /// `enabledTemplateIDs` 为 nil 时用默认子集；非 nil 时严格按用户选择（空数组＝不显示任何内置）。
    func resolvedTemplates() -> [TemplateEntry] {
        let enabledIDs = enabledTemplateIDs ?? FinderMenuPresets.defaultEnabledTemplateIDs
        let presetEntries = FinderMenuPresets.fileTemplates
            .filter { enabledIDs.contains($0.id) }
            .map { TemplateEntry(id: $0.id, title: $0.title, fileExtension: $0.fileExtension, content: $0.content) }
        return presetEntries + templates
    }

    static let empty = FinderMenuConfig()
}
