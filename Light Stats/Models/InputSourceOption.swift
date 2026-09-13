//
//  InputSourceOption.swift
//  Light Stats
//
//  一个可选输入源（键盘布局 / 输入法模式）的展示快照。纯数据，不含任何 TIS 调用 ——
//  枚举与切换都在 `DefaultInputSourceService`。
//

import Foundation

nonisolated struct InputSourceOption: Sendable, Hashable, Identifiable {
    /// TIS input source ID，例如 `com.tencent.inputmethod.wetype.pinyin`。
    let id: String
    /// 系统给出的本地化显示名，例如「微信输入法」。
    let name: String
}

extension InputSourceOption {
    /// 归一化系统枚举结果：丢弃空 id、按 id 去重（保留首个）、按名称排序。
    ///
    /// TIS 列表会把同一个输入法的不同 mode 各列一条，也可能出现重复项；选择器里
    /// 只应出现一次，且顺序必须可预期（名称相同时用 id 兜底，避免排序不稳定）。
    nonisolated static func normalize(_ candidates: [InputSourceOption]) -> [InputSourceOption] {
        var seen = Set<String>()
        let unique = candidates.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        return unique.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            guard order == .orderedSame else { return order == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
}
