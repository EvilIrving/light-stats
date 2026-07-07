//
//  FinderMenuCommand.swift
//  Light Stats / FinderMenuExtension
//
//  绑定到 NSMenuItem.representedObject 的命令载荷：动作 + 可选参数（模板 id /
//  目标目录路径 / App bundle id）+ 菜单生成时捕获的 Finder 上下文。
//

import Foundation

nonisolated struct FinderMenuCommand: Sendable {
    let action: FinderMenuAction
    let parameter: String?
    let paths: [String]
    let container: String?

    init(_ action: FinderMenuAction, parameter: String? = nil, paths: [String] = [], container: String? = nil) {
        self.action = action
        self.parameter = parameter
        self.paths = paths
        self.container = container
    }
}
