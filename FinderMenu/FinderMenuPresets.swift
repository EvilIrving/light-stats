//
//  FinderMenuPresets.swift
//  Light Stats / FinderMenuExtension
//
//  P2 的内置预设：新建文件模板、常用目录、可选「打开方式」App 候选。
//  保持纯 Foundation（无 AppKit），App 是否安装的过滤放在扩展侧用 NSWorkspace 做。
//  P3 接入用户可编辑列表时，这里的预设作为兜底默认值。
//

import Foundation

nonisolated enum FinderMenuPresets {

    // MARK: - New File Templates

    struct FileTemplate: Sendable {
        let id: String
        let title: String
        let fileExtension: String
        let content: String
    }

    static let fileTemplates: [FileTemplate] = [
        FileTemplate(id: "txt", title: "Text (.txt)", fileExtension: "txt", content: ""),
        FileTemplate(id: "md", title: "Markdown (.md)", fileExtension: "md", content: ""),
        FileTemplate(id: "json", title: "JSON (.json)", fileExtension: "json", content: "{\n}\n")
    ]

    static func template(id: String) -> FileTemplate? {
        fileTemplates.first { $0.id == id }
    }

    // MARK: - Favorite Directories

    struct FavoriteDirectory: Sendable {
        let name: String
        let path: String
    }

    static func favoriteDirectories() -> [FavoriteDirectory] {
        let home = FinderMenuShared.realHomeDirectory() as NSString
        return ["Downloads", "Desktop", "Documents"].map {
            FavoriteDirectory(name: $0, path: home.appendingPathComponent($0))
        }
    }

    // MARK: - Open-With App Candidates

    struct AppPreset: Sendable {
        let name: String
        let bundleID: String
    }

    /// 候选 App；扩展侧按是否安装过滤后才进菜单。
    static let appCandidates: [AppPreset] = [
        AppPreset(name: "Terminal", bundleID: "com.apple.Terminal"),
        AppPreset(name: "iTerm", bundleID: "com.googlecode.iterm2"),
        AppPreset(name: "VS Code", bundleID: "com.microsoft.VSCode"),
        AppPreset(name: "Sublime Text", bundleID: "com.sublimetext.4"),
        AppPreset(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92")
    ]
}
