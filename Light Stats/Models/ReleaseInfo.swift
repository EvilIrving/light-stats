//
//  ReleaseInfo.swift
//  Light Stats
//
//  自动更新所需的数据模型：语义化版本号 + GitHub Release 描述。
//  纯数据，无逻辑依赖；供 UpdateService（actor）与 UpdateManager（@MainActor）共用。
//

import Foundation

/// 语义化版本号，支持任意段数的数字比较（"1.2.10" > "1.2.9"）。
/// 忽略前缀 v/V 与 `-beta` / `+build` 之类后缀，只比较主版本数字段。
nonisolated struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]
    let raw: String

    init?(_ input: String) {
        var string = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("v") || string.hasPrefix("V") { string.removeFirst() }
        // 去掉 "-beta" / "+build" 等元数据，只取核心 "x.y.z"。
        let core = string.split(whereSeparator: { $0 == "-" || $0 == "+" })
            .first.map(String.init) ?? string
        let parsed = core.split(separator: ".").map { Int($0) }
        guard !parsed.isEmpty, !parsed.contains(where: { $0 == nil }) else { return nil }
        components = parsed.compactMap { $0 }
        raw = input
    }

    var description: String { raw }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// 一个可安装的发布版本：版本号、更新说明、DMG 下载地址、Release 页面地址。
nonisolated struct ReleaseInfo: Sendable, Equatable {
    let tagName: String
    let version: SemanticVersion
    let releaseNotes: String
    let downloadURL: URL
    let htmlURL: URL

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }

    private struct Response: Decodable {
        let tag_name: String
        let body: String?
        let html_url: String?
        let prerelease: Bool?
        let draft: Bool?
        let assets: [Asset]
    }

    /// 解析 GitHub `releases/latest`（单对象）。该 endpoint 天然排除 draft/prerelease，
    /// 这里再拒绝一次以防 GitHub 行为变化——稳定通道（自动检查）专用。
    init?(json data: Data) {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        self.init(response: response, allowPrerelease: false)
    }

    /// 解析 GitHub `releases`（列表，按发布时间倒序）。取首个满足条件的版本。
    /// `allowPrerelease == true` 时接受预发布版本——供「立即检查」的内测通道使用，
    /// 让手动检查能拿到 beta，而自动检查仍只走稳定的 `releases/latest`。
    static func first(fromListJSON data: Data, allowPrerelease: Bool) -> ReleaseInfo? {
        guard let responses = try? JSONDecoder().decode([Response].self, from: data) else { return nil }
        for response in responses {
            if let info = ReleaseInfo(response: response, allowPrerelease: allowPrerelease) {
                return info
            }
        }
        return nil
    }

    /// 从单个 Release 响应构造。draft 一律拒绝；prerelease 仅在显式放行时接受；
    /// 无可用 `.dmg` 资产或版本号非法时返回 nil。
    private init?(response: Response, allowPrerelease: Bool) {
        guard response.draft != true else { return nil }
        guard allowPrerelease || response.prerelease != true else { return nil }
        guard let semantic = SemanticVersion(response.tag_name) else { return nil }
        guard let dmg = response.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
              let url = URL(string: dmg.browser_download_url) else { return nil }

        tagName = response.tag_name
        version = semantic
        releaseNotes = response.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        downloadURL = url
        htmlURL = response.html_url.flatMap(URL.init(string:)) ?? url
    }
}
