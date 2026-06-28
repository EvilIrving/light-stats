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

    /// 内置文件类型预设（一二十个常用类型）。用户在设置里勾选哪些显示在「新建文件」
    /// 子菜单；空白/极简内容是有意的——只是个起点文件，不是脚手架。
    static let fileTemplates: [FileTemplate] = [
        FileTemplate(id: "txt", title: "Text (.txt)", fileExtension: "txt", content: ""),
        FileTemplate(id: "md", title: "Markdown (.md)", fileExtension: "md", content: "# \n"),
        FileTemplate(id: "html", title: "HTML (.html)", fileExtension: "html",
                     content: "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title></title>\n</head>\n<body>\n</body>\n</html>\n"),
        FileTemplate(id: "css", title: "CSS (.css)", fileExtension: "css", content: ""),
        FileTemplate(id: "js", title: "JavaScript (.js)", fileExtension: "js", content: ""),
        FileTemplate(id: "ts", title: "TypeScript (.ts)", fileExtension: "ts", content: ""),
        FileTemplate(id: "json", title: "JSON (.json)", fileExtension: "json", content: "{\n}\n"),
        FileTemplate(id: "yaml", title: "YAML (.yaml)", fileExtension: "yaml", content: ""),
        FileTemplate(id: "xml", title: "XML (.xml)", fileExtension: "xml", content: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"),
        FileTemplate(id: "csv", title: "CSV (.csv)", fileExtension: "csv", content: ""),
        FileTemplate(id: "toml", title: "TOML (.toml)", fileExtension: "toml", content: ""),
        FileTemplate(id: "sh", title: "Shell (.sh)", fileExtension: "sh", content: "#!/bin/bash\nset -euo pipefail\n\n"),
        FileTemplate(id: "py", title: "Python (.py)", fileExtension: "py", content: ""),
        FileTemplate(id: "swift", title: "Swift (.swift)", fileExtension: "swift", content: ""),
        FileTemplate(id: "go", title: "Go (.go)", fileExtension: "go", content: "package main\n"),
        FileTemplate(id: "rs", title: "Rust (.rs)", fileExtension: "rs", content: ""),
        FileTemplate(id: "c", title: "C (.c)", fileExtension: "c", content: ""),
        FileTemplate(id: "cpp", title: "C++ (.cpp)", fileExtension: "cpp", content: ""),
        FileTemplate(id: "java", title: "Java (.java)", fileExtension: "java", content: ""),
        FileTemplate(id: "sql", title: "SQL (.sql)", fileExtension: "sql", content: "")
    ]

    /// 干净安装默认显示的类型（其余靠用户勾选）。保守取最通用的两个，避免菜单过长。
    static let defaultEnabledTemplateIDs: [String] = ["txt", "md"]

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
