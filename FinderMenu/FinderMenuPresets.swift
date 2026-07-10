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

    // MARK: - Terminal Presets

    struct TerminalPreset: Sendable, Identifiable, Hashable {
        let id: String
        let name: String
        let bundleID: String?
    }

    static let defaultTerminalID = "terminal"

    static let terminalPresets: [TerminalPreset] = [
        TerminalPreset(id: "terminal", name: "Terminal", bundleID: "com.apple.Terminal"),
        TerminalPreset(id: "iterm2", name: "iTerm2", bundleID: "com.googlecode.iterm2"),
        TerminalPreset(id: "ghostty", name: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        TerminalPreset(id: "wezterm", name: "WezTerm", bundleID: "com.github.wez.wezterm"),
        TerminalPreset(id: "alacritty", name: "Alacritty", bundleID: "org.alacritty"),
        TerminalPreset(id: "kitty", name: "kitty", bundleID: "net.kovidgoyal.kitty"),
        TerminalPreset(id: "warp", name: "Warp", bundleID: "dev.warp.Warp-Stable"),
        TerminalPreset(id: "cmux", name: "cmux", bundleID: "com.cmuxterm.app")
    ]

    static func normalizeTerminalID(_ id: String) -> String {
        terminalPresets.contains { $0.id == id } ? id : defaultTerminalID
    }

    static func terminalPreset(id: String) -> TerminalPreset {
        terminalPresets.first { $0.id == id } ?? terminalPresets[0]
    }

    // MARK: - New File Templates

    /// 文件类型分类。设置页按此分组、可折叠；普通用户常用的「文档/文本」在前，「代码」在后。
    /// 仅持 `titleKey`（本地化键），不依赖 AppKit / 本地化实现，保持模型层纯净。
    enum TemplateCategory: String, CaseIterable, Sendable {
        case document   // 文档与文本
        case web        // 网页与标记
        case data       // 数据与配置
        case code       // 代码

        var titleKey: String {
            switch self {
            case .document: return "finderMenu.templateCategory.document"
            case .web: return "finderMenu.templateCategory.web"
            case .data: return "finderMenu.templateCategory.data"
            case .code: return "finderMenu.templateCategory.code"
            }
        }
    }

    struct FileTemplate: Sendable {
        let id: String
        let title: String
        let fileExtension: String
        let content: String
        let category: TemplateCategory
    }

    /// 内置文件类型预设，按分类分组（数组顺序即菜单/设置顺序：文档优先，代码靠后）。
    /// 空白/极简内容是有意的——只是个合法的起点文件，不是脚手架。
    static let fileTemplates: [FileTemplate] = [
        // 文档与文本
        FileTemplate(id: "txt", title: "Text (.txt)", fileExtension: "txt", content: "", category: .document),
        FileTemplate(id: "md", title: "Markdown (.md)", fileExtension: "md", content: "# \n", category: .document),
        FileTemplate(id: "rtf", title: "Rich Text (.rtf)", fileExtension: "rtf",
                     content: "{\\rtf1\\ansi\\deff0\n}\n", category: .document),
        FileTemplate(id: "csv", title: "CSV (.csv)", fileExtension: "csv", content: "", category: .document),
        FileTemplate(id: "tsv", title: "TSV (.tsv)", fileExtension: "tsv", content: "", category: .document),
        FileTemplate(id: "log", title: "Log (.log)", fileExtension: "log", content: "", category: .document),
        FileTemplate(id: "tex", title: "LaTeX (.tex)", fileExtension: "tex",
                     content: "\\documentclass{article}\n\\begin{document}\n\n\\end{document}\n", category: .document),
        // 网页与标记
        FileTemplate(id: "html", title: "HTML (.html)", fileExtension: "html",
                     content: """
                     <!DOCTYPE html>
                     <html lang="en">
                     <head>
                       <meta charset="UTF-8">
                       <meta name="viewport" content="width=device-width, initial-scale=1.0">
                       <title></title>
                     </head>
                     <body>
                     </body>
                     </html>

                     """,
                     category: .web),
        FileTemplate(id: "css", title: "CSS (.css)", fileExtension: "css", content: "", category: .web),
        FileTemplate(id: "xml", title: "XML (.xml)", fileExtension: "xml",
                     content: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n", category: .web),
        FileTemplate(id: "svg", title: "SVG (.svg)", fileExtension: "svg",
                     content: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\n</svg>\n", category: .web),
        FileTemplate(id: "rst", title: "reStructuredText (.rst)", fileExtension: "rst", content: "", category: .web),
        // 数据与配置
        FileTemplate(id: "json", title: "JSON (.json)", fileExtension: "json", content: "{\n}\n", category: .data),
        FileTemplate(id: "yaml", title: "YAML (.yaml)", fileExtension: "yaml", content: "", category: .data),
        FileTemplate(id: "toml", title: "TOML (.toml)", fileExtension: "toml", content: "", category: .data),
        FileTemplate(id: "ini", title: "INI (.ini)", fileExtension: "ini", content: "", category: .data),
        FileTemplate(id: "conf", title: "Config (.conf)", fileExtension: "conf", content: "", category: .data),
        // 代码
        FileTemplate(id: "js", title: "JavaScript (.js)", fileExtension: "js", content: "", category: .code),
        FileTemplate(id: "ts", title: "TypeScript (.ts)", fileExtension: "ts", content: "", category: .code),
        FileTemplate(id: "py", title: "Python (.py)", fileExtension: "py", content: "", category: .code),
        FileTemplate(id: "sh", title: "Shell (.sh)", fileExtension: "sh",
                     content: "#!/bin/bash\nset -euo pipefail\n\n", category: .code),
        FileTemplate(id: "swift", title: "Swift (.swift)", fileExtension: "swift", content: "", category: .code),
        FileTemplate(id: "go", title: "Go (.go)", fileExtension: "go", content: "package main\n", category: .code),
        FileTemplate(id: "rs", title: "Rust (.rs)", fileExtension: "rs", content: "", category: .code),
        FileTemplate(id: "rb", title: "Ruby (.rb)", fileExtension: "rb", content: "", category: .code),
        FileTemplate(id: "php", title: "PHP (.php)", fileExtension: "php", content: "<?php\n", category: .code),
        FileTemplate(id: "c", title: "C (.c)", fileExtension: "c", content: "", category: .code),
        FileTemplate(id: "cpp", title: "C++ (.cpp)", fileExtension: "cpp", content: "", category: .code),
        FileTemplate(id: "java", title: "Java (.java)", fileExtension: "java", content: "", category: .code),
        FileTemplate(id: "sql", title: "SQL (.sql)", fileExtension: "sql", content: "", category: .code)
    ]

    /// 干净安装默认显示的类型（其余靠用户勾选）。保守取最通用的两个，避免菜单过长。
    static let defaultEnabledTemplateIDs: [String] = ["txt", "md"]

    /// 某分类下的预设（保持数组定义顺序）。
    static func fileTemplates(in category: TemplateCategory) -> [FileTemplate] {
        fileTemplates.filter { $0.category == category }
    }

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
