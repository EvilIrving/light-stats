//
//  FinderMenuShared.swift
//  Light Stats / FinderMenuExtension
//
//  Finder 右键菜单宿主进程与扩展进程之间的共享常量与配置门面。
//  同一份源码同时编译进「Light Stats」宿主与「FinderMenuExtension」扩展两个 target。
//
//  关键：扩展是独立沙盒进程，读不到宿主的 `UserDefaults.standard`，也无法直接调用
//  宿主代码。两者只能通过 App Group 容器（共享配置）+ CFMessagePort（实时动作）通信。
//  下面的标识都以 App Group ID 为前缀——沙盒进程只能查找以自身 App Group 命名的
//  mach 服务，端口名不带前缀会被沙盒拒绝、扩展静默连不上宿主。
//
//  标 `nonisolated`：纯常量与无状态读写，供宿主 MainActor 与扩展的 nonisolated
//  C 回调两侧直接调用，无需 actor 隔离（沿用 AppConfig 的写法）。
//

import Foundation

nonisolated enum FinderMenuShared {
    /// App Group 标识。Developer ID（非 MAS）分发下用 Team ID 前缀形式，前缀须等于
    /// 实际签名团队。本项目签名团队是 QZZ878S3NS（Developer ID: TIANBAO DONG），
    /// debug-run.sh 与发布流程都用它。
    static let appGroupID = "QZZ878S3NS.com.light-stats.shared"

    /// 宿主注册的 CFMessagePort 本地端口名；扩展按此名做 remote 查找。前缀须落在
    /// App Group 命名空间内，否则沙盒扩展无权查找该 mach 服务。
    static let messagePortName = "QZZ878S3NS.com.light-stats.shared.findermenu"

    /// 宿主 App 的 bundle id，供扩展在宿主未运行时拉起它。
    static let hostBundleID = "cain.com.light-stats"

    /// FinderSync 扩展的 bundle id，供宿主用 pluginkit 查询其注册 / 启用状态。
    static let extensionBundleID = "cain.com.light-stats.FinderMenuExtension"

    /// 共享配置的 UserDefaults suite 名（与 App Group 同名）。
    static let defaultsSuiteName = appGroupID

    private static let enabledKey = "findermenu.enabled"
    private static let configKey = "findermenu.config"
    private static let labelsKey = "findermenu.labels"
    private static let pendingFailureKey = "findermenu.pendingFailure"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: defaultsSuiteName)
    }

    /// 总开关镜像值。宿主在设置变更时写入；扩展在 `menu(for:)` 中读取以决定是否出菜单。
    static func isEnabled() -> Bool {
        sharedDefaults?.bool(forKey: enabledKey) ?? false
    }

    static func setEnabled(_ value: Bool) {
        sharedDefaults?.set(value, forKey: enabledKey)
        sharedDefaults?.synchronize()
    }

    /// 读用户可编辑配置（常用目录 / 打开方式 App）。缺省 / 解码失败 → 空配置（沿用预设）。
    static func loadConfig() -> FinderMenuConfig {
        guard let data = sharedDefaults?.data(forKey: configKey),
              let config = try? JSONDecoder().decode(FinderMenuConfig.self, from: data) else {
            return .empty
        }
        return config
    }

    /// 写用户可编辑配置。扩展在下次 menu(for:) 时实时读取，无需通知。
    static func saveConfig(_ config: FinderMenuConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        sharedDefaults?.set(data, forKey: configKey)
        sharedDefaults?.synchronize()
    }

    /// 本地化菜单标题字典（key = 动作 rawValue）。宿主用自身语言计算好写入，扩展读取——
    /// 因为 `.localized` 依赖宿主 bundle 与宿主 standard defaults，在沙盒扩展里取不到。
    static func setLabels(_ labels: [String: String]) {
        guard let data = try? JSONEncoder().encode(labels) else { return }
        sharedDefaults?.set(data, forKey: labelsKey)
        sharedDefaults?.synchronize()
    }

    /// 取某动作的本地化标题；未发布时返回 nil，由调用方回退到英文字面量。
    static func label(for key: String) -> String? {
        guard let data = sharedDefaults?.data(forKey: labelsKey),
              let labels = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return labels[key]
    }

    /// 沙盒进程的真实主目录。`getpwuid` 直接读系统用户数据库，不受 App Sandbox 的
    /// 路径重定向影响（NSHomeDirectory() 在沙盒里返回容器路径）；失败时回退。
    static func realHomeDirectory() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    // MARK: - Pending failure (IPC delivery failed while host was down)

    /// 扩展侧 IPC 发送失败时写入，宿主启动时读取并 toast，然后清除。
    /// 存 action rawValue + Unix timestamp，Host 看到后生成可读的失败提示。
    static func writePendingFailure(action: String) {
        let entry: [String: Any] = ["action": action, "timestamp": Date().timeIntervalSince1970]
        sharedDefaults?.set(entry, forKey: pendingFailureKey)
        sharedDefaults?.synchronize()
    }

    /// 宿主启动时调用：返回待 toast 的 action rawValue（如果有），并立即清除。
    /// 返回 nil 表示没有挂起的失败。
    static func consumePendingFailure() -> String? {
        guard let entry = sharedDefaults?.dictionary(forKey: pendingFailureKey),
              let action = entry["action"] as? String else {
            return nil
        }
        sharedDefaults?.removeObject(forKey: pendingFailureKey)
        sharedDefaults?.synchronize()
        return action
    }
}
