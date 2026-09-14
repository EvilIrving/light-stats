//
//  FinderMenuCommand.swift
//  Light Stats / FinderMenuExtension
//
//  FinderSync 扩展内部的命令载荷：动作 + 可选参数（模板 id /
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

/// 菜单项 tag → 命令的寄存表。
///
/// FinderSync 会把扩展返回的 `NSMenu` 编组后交给 Finder 显示，点击再回调扩展；跨这一趟
/// **只有 `NSMenuItem.tag` 还在，`representedObject` 会变成 nil**。所以命令必须按 tag 寄存。
///
/// 而且不能每次重建菜单就清空：Finder 完全可能在旧菜单还开着的时候重建一次（右键空白处、
/// 切目录、挂载卷）。1.9.2 在 `menu(for:)` 开头 `removeAll()`，重建后点旧菜单就查不到命令；
/// 1.9.3 改用 `representedObject`，结果所有点击都查不到。这里 tag 不复用、表不主动清空，
/// 只按容量淘汰最旧的，两种毛病都不会再出现。
nonisolated final class FinderMenuCommandRegistry {

    private var commands: [Int: FinderMenuCommand] = [:]
    private var nextTag = 1
    private let capacity: Int

    /// `capacity` 是保留窗口：最近这么多条命令始终可查，更早的按 tag 从小到大淘汰。
    init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
    }

    /// 寄存一条命令，返回它的菜单项 tag。tag 从 1 开始单调递增，永不复用。
    func register(_ command: FinderMenuCommand) -> Int {
        let tag = nextTag
        nextTag += 1
        commands[tag] = command
        let overflow = commands.count - capacity
        if overflow > 0 {
            for key in commands.keys.sorted().prefix(overflow) {
                commands.removeValue(forKey: key)
            }
        }
        return tag
    }

    /// 点击回调用它取回命令。tag 不认得时返回 nil——调用方必须显式处理这种情况，
    /// 不要像 1.9.3 那样静默 `return`，否则整份菜单的点击都会无声消失。
    func command(for tag: Int) -> FinderMenuCommand? {
        commands[tag]
    }

    /// 当前寄存的命令条数，上限为 `capacity`。
    var count: Int { commands.count }
}
