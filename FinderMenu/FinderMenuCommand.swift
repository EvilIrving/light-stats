//
//  FinderMenuCommand.swift
//  Light Stats / FinderMenuExtension
//
//  绑定到 NSMenuItem.representedObject 的命令载荷：动作 + 可选参数（模板 id /
//  目标目录路径 / App bundle id）。点击时由 runAction 取回，转成 FinderMenuRequest。
//

import Foundation

nonisolated struct FinderMenuCommand: Sendable {
    let action: FinderMenuAction
    let parameter: String?

    init(_ action: FinderMenuAction, parameter: String? = nil) {
        self.action = action
        self.parameter = parameter
    }
}
