//
//  FinderMenuAction.swift
//  Light Stats / FinderMenuExtension
//
//  Finder 右键菜单的动作标识。`copy*` 在扩展进程内直接完成（纯剪贴板，无文件 IO）；
//  其余动作通过 CFMessagePort 委派给非沙盒宿主执行，绕开扩展沙盒的文件写入限制。
//
//  `nonisolated` + `Codable`：随 FinderMenuRequest 走 JSON 编码跨进程传输，并在
//  两侧的 nonisolated 上下文（含宿主的 C 回调）中自由读取。
//

import Foundation

nonisolated enum FinderMenuAction: String, Sendable, Codable, CaseIterable {
    case copyPath          // 扩展内：拷贝完整路径到剪贴板
    case copyName          // 扩展内：拷贝文件名到剪贴板
    case openTerminalHere  // 委派宿主：在当前目录打开终端
    case newFile           // 委派宿主：在容器目录按模板新建文件（parameter = 模板 id）
    case moveTo            // 委派宿主：把选中项移动到目标目录（parameter = 目标目录路径）
    case copyTo            // 委派宿主：把选中项复制到目标目录（parameter = 目标目录路径）
    case openWithApp       // 委派宿主：用指定 App 打开选中项（parameter = App bundle id）
    case toggleHidden      // 委派宿主：切换选中项的隐藏标志
    case cmuxNewWindow     // 委派宿主：调用 cmux 的 macOS Service 在当前目录新开窗口
    case cmuxNewWorkspace  // 委派宿主：调用 cmux 的 macOS Service 在当前目录新开工作区

    /// 是否需要委派给宿主（true）还是扩展内自理（false）。
    var requiresHost: Bool {
        switch self {
        case .copyPath, .copyName: return false
        case .openTerminalHere, .newFile, .moveTo, .copyTo, .openWithApp, .toggleHidden,
             .cmuxNewWindow, .cmuxNewWorkspace: return true
        }
    }

    /// 本地化标题：优先读宿主发布到 App Group 的标签，未发布则回退英文字面量。
    /// 扩展进程不能用 `.localized`（依赖宿主 bundle / 宿主 defaults），故走此路径。
    var localizedTitle: String {
        FinderMenuShared.label(for: rawValue) ?? defaultTitle
    }

    /// 英文字面量标题，作为本地化标签的兜底。带参数的动作（newFile/moveTo/copyTo/
    /// openWithApp）此处是子菜单标题，叶子项标题由参数（目录名 / App 名 / 模板名）决定。
    var defaultTitle: String {
        switch self {
        case .copyPath: return "Copy Path"
        case .copyName: return "Copy Name"
        case .openTerminalHere: return "Open Terminal Here"
        case .newFile: return "New File"
        case .moveTo: return "Move To"
        case .copyTo: return "Copy To"
        case .openWithApp: return "Open With"
        case .toggleHidden: return "Hide / Show"
        case .cmuxNewWindow: return "New cmux Window Here"
        case .cmuxNewWorkspace: return "New cmux Workspace Here"
        }
    }
}
