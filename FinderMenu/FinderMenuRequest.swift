//
//  FinderMenuRequest.swift
//  Light Stats / FinderMenuExtension
//
//  扩展 → 宿主的一次动作请求。经 JSON 编码走 CFMessagePort 传输。
//  `nonisolated`：编解码在扩展的 perform（MainActor）与宿主的 C 回调（nonisolated）
//  两侧都要调用，不能带 actor 隔离。
//

import Foundation

nonisolated struct FinderMenuRequest: Codable, Sendable {
    let action: FinderMenuAction
    let paths: [String]       // 选中项的文件系统路径
    let container: String?    // 右键所在目录（空白处 / 容器菜单时使用）
    let parameter: String?    // 动作参数：模板 id / 目标目录路径 / App bundle id

    init(action: FinderMenuAction, paths: [String], container: String?, parameter: String? = nil) {
        self.action = action
        self.paths = paths
        self.container = container
        self.parameter = parameter
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) -> FinderMenuRequest? {
        try? JSONDecoder().decode(FinderMenuRequest.self, from: data)
    }
}
