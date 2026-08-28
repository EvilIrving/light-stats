//
//  ReleaseInfo.swift
//  Light Stats
//
//  自动更新所需的数据模型：语义化版本号 + GitHub Release 描述。
//  纯数据，无逻辑依赖；供 UpdateService（actor）与 UpdateManager（@MainActor）共用。
//

import Foundation

/// 语义化版本号，支持任意段数的数字比较（"1.2.10" > "1.2.9"）。
/// 遵循 SemVer 2.0：忽略前缀 v/V 与 `+build` 元数据；预发布标识（`-beta.1`）参与比较——
/// 同核心版本下正式版 > 预发布版，预发布标识按点分段比较（数字段数值比，字母段字典序；
/// 数字段 < 字母段；公共前缀相同则更长者更高）。
nonisolated struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]
    /// 预发布标识序列；空 = 正式版。
    let prerelease: [PrereleaseIdentifier]
    let raw: String

    enum PrereleaseIdentifier: Comparable, Sendable, Equatable {
        case numeric(Int)
        case text(String)

        static func < (lhs: PrereleaseIdentifier, rhs: PrereleaseIdentifier) -> Bool {
            switch (lhs, rhs) {
            case (.numeric(let left), .numeric(let right)): return left < right
            case (.text(let left), .text(let right)): return left < right
            case (.numeric, .text): return true
            case (.text, .numeric): return false
            }
        }
    }

    init?(_ input: String) {
        var string = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("v") || string.hasPrefix("V") { string.removeFirst() }
        // 丢弃 `+build` 元数据（不参与比较）。
        let withoutBuild = string.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? string
        // 核心版本与预发布标识以首个 `-` 分隔。
        let coreAndPre = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = String(coreAndPre[0])
        let parsed = core.split(separator: ".").map { Int($0) }
        guard !parsed.isEmpty, !parsed.contains(where: { $0 == nil }) else { return nil }
        components = parsed.compactMap { $0 }
        if coreAndPre.count > 1 {
            prerelease = String(coreAndPre[1]).split(separator: ".").map { ident in
                let token = String(ident)
                if let number = Int(token), String(number) == token {
                    return .numeric(number)
                }
                return .text(token)
            }
        } else {
            prerelease = []
        }
        raw = input
    }

    var description: String { raw }

    /// 是否为预发布版本（含 `-beta` / `-rc` 等）。
    var isPrerelease: Bool { !prerelease.isEmpty }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        // 核心相等：正式版 > 预发布；两侧皆预发布则按标识序列比较。
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false
        case (false, true): return true
        case (false, false):
            let limit = max(lhs.prerelease.count, rhs.prerelease.count)
            for index in 0..<limit {
                if index >= lhs.prerelease.count { return true }
                if index >= rhs.prerelease.count { return false }
                if lhs.prerelease[index] != rhs.prerelease[index] {
                    return lhs.prerelease[index] < rhs.prerelease[index]
                }
            }
            return false
        }
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
    /// R2 通道提供的 DMG SHA-256 校验文件地址；GitHub 资产无此文件时为 nil（跳过哈希校验）。
    let sha256URL: URL?

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

    /// R2 渠道标记文件（`latest-stable.json` / `latest-beta.json`）：
    /// `{"version":"1.9.2","file":"Light-Stats-1.9.2.dmg","notes":"..."}`。
    private struct Manifest: Decodable {
        let version: String
        let file: String
        let notes: String?
    }

    /// R2 对象地址前缀：版本固定 DMG 与 `.sha256` 校验文件均在此域名下直读。
    static let r2BaseURL = URL(string: "https://download.onecat.dev")!

    /// 解析 R2 渠道标记。版本号非法或缺少文件名时返回 nil。
    init?(manifest data: Data) {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              !manifest.file.isEmpty,
              let semantic = SemanticVersion(manifest.version),
              let url = URL(string: "\(Self.r2BaseURL.absoluteString)/\(manifest.file)") else { return nil }

        tagName = "v" + manifest.version
        version = semantic
        releaseNotes = manifest.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        downloadURL = url
        htmlURL = URL(string: "https://github.com/EvilIrving/light-stats/releases/tag/\(tagName)") ?? url
        sha256URL = URL(string: "\(url.absoluteString).sha256")
    }

    /// 解析 GitHub `releases/latest`（单对象）。该 endpoint 天然排除 draft/prerelease，
    /// 这里再拒绝一次以防 GitHub 行为变化——稳定通道（自动检查）专用。
    init?(json data: Data) {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        self.init(response: response, allowPrerelease: false)
    }

    /// 解析 GitHub `releases`（列表，按发布时间倒序）。取首个满足条件的版本。
    /// `allowPrerelease == true` 时接受预发布版本——用户开启「尝鲜 Beta」后，
    /// 自动/手动检查都走列表端点以纳入 prerelease。
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
        sha256URL = nil
    }
}
