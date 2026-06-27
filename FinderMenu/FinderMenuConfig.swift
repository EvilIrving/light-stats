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

    init(favoriteDirectories: [DirectoryEntry] = [],
         openWithApps: [AppEntry] = [],
         templates: [TemplateEntry] = []) {
        self.favoriteDirectories = favoriteDirectories
        self.openWithApps = openWithApps
        self.templates = templates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoriteDirectories = try container.decodeIfPresent([DirectoryEntry].self, forKey: .favoriteDirectories) ?? []
        openWithApps = try container.decodeIfPresent([AppEntry].self, forKey: .openWithApps) ?? []
        templates = try container.decodeIfPresent([TemplateEntry].self, forKey: .templates) ?? []
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

    /// 新建文件模板：用户配置非空则用配置，否则映射内置预设。
    func resolvedTemplates() -> [TemplateEntry] {
        guard templates.isEmpty else { return templates }
        return FinderMenuPresets.fileTemplates.map {
            TemplateEntry(id: $0.id, title: $0.title, fileExtension: $0.fileExtension, content: $0.content)
        }
    }

    static let empty = FinderMenuConfig()
}
