//
//  SettingsManager.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// 标 `nonisolated`：纯常量，供采集 actor / 服务直接读取（如电池缓存 TTL）。
nonisolated enum AppConfig {
    static let topCPUProcessCount: Int = 5
    static let topMemoryProcessCount: Int = 300
    /// 进程榜仅在弹窗内展示；CPU 使用系统 ps，内存使用原生 footprint 采样。
    /// 单独节流，避免跟随主采样周期高频遍历全进程表。
    static let topProcessRefreshInterval: TimeInterval = 5.0
    static let appMemoryRefreshInterval: TimeInterval = 5.0
    /// 出口节点探测缓存有效期：TTL 内不重复发外部请求。
    static let exitNodeCacheTTL: TimeInterval = 60
    /// 电池慢变量（循环/健康/功耗/温度）缓存有效期：TTL 内不重复读 IORegistry。
    static let batteryHealthCacheTTL: TimeInterval = 30
    /// AI 用量刷新间隔固定为 2 分钟，降低令牌长时间闲置后失效的概率。
    static let aiUsageRefreshInterval: TimeInterval = 120
    /// 正式收费前保持开启：每个启动过本版本的用户都会永久获赠 Pro。
    /// 首个正式收费版本改为 false；已写入的赠送资格仍永久有效。
    static let proGiftEnabled = true
}

/// User settings for the menu stats app
@MainActor
protocol SettingsManaging: ObservableObject {
    var showLogo: Bool { get set }
    var showCPU: Bool { get set }
    var showGPU: Bool { get set }
    var showMemory: Bool { get set }
    var showDisk: Bool { get set }
    var showNetwork: Bool { get set }
    var showFan: Bool { get set }
    var showBattery: Bool { get set }
    var showHealth: Bool { get set }
    var healthIncludeCPU: Bool { get set }
    var healthIncludeMemory: Bool { get set }
    var healthIncludeLoad: Bool { get set }
    var healthIncludeTemperature: Bool { get set }
    var healthIncludeGPU: Bool { get set }
    var healthIncludePower: Bool { get set }
    var useColorIndicator: Bool { get set }
    var appTheme: AppTheme { get set }
    var refreshRate: SettingsManager.RefreshRate { get set }
    var temperatureUnit: SettingsManager.TemperatureUnit { get set }
    var exitNodeDetectionEnabled: Bool { get set }
    var exitNodeProvider: ExitNodeProvider { get set }
    var autoCheckUpdates: Bool { get set }
    var includeBetaUpdates: Bool { get set }
    var windowManagementEnabled: Bool { get set }
    var defaultInputSourceEnabled: Bool { get set }
    var defaultInputSourceID: String? { get set }
    var findMouseEnabled: Bool { get set }
    var findMouseTriggerKey: FindMouseTriggerKey { get set }
    var presentationCursorStyle: PresentationCursorStyle { get set }
    var cleanupPanelHotKeyEnabled: Bool { get set }
    var cleanupPanelHotKey: PanelHotKey { get set }
    var activationCode: String? { get set }
    /// 赠送期用户或收费前老用户享有的永久 Pro 资格。
    var isGrandfathered: Bool { get }
    var displayBrightnessControlEnabled: Bool { get set }
    var finderMenuEnabled: Bool { get set }
}

@MainActor
final class SettingsManager: ObservableObject, SettingsManaging {
    private let defaults: UserDefaults

    // MARK: - Status Bar Display Settings

    @Published var showLogo: Bool {
        didSet { save(showLogo, for: .showLogo) }
    }
    @Published var showCPU: Bool {
        didSet { save(showCPU, for: .showCPU) }
    }
    @Published var showGPU: Bool {
        didSet { save(showGPU, for: .showGPU) }
    }
    @Published var showMemory: Bool {
        didSet { save(showMemory, for: .showMemory) }
    }
    @Published var showDisk: Bool {
        didSet { save(showDisk, for: .showDisk) }
    }
    @Published var showNetwork: Bool {
        didSet { save(showNetwork, for: .showNetwork) }
    }
    @Published var showFan: Bool {
        didSet { save(showFan, for: .showFan) }
    }
    @Published var showBattery: Bool {
        didSet { save(showBattery, for: .showBattery) }
    }
    @Published var showHealth: Bool {
        didSet { save(showHealth, for: .showHealth) }
    }

    // MARK: - Health Score Dimensions
    // 哪些维度参与健康分计算（逐项开关）。关闭的维度权重自动重分配到其余维度。

    @Published var healthIncludeCPU: Bool {
        didSet { save(healthIncludeCPU, for: .healthIncludeCPU) }
    }
    @Published var healthIncludeMemory: Bool {
        didSet { save(healthIncludeMemory, for: .healthIncludeMemory) }
    }
    @Published var healthIncludeLoad: Bool {
        didSet { save(healthIncludeLoad, for: .healthIncludeLoad) }
    }
    @Published var healthIncludeTemperature: Bool {
        didSet { save(healthIncludeTemperature, for: .healthIncludeTemperature) }
    }
    @Published var healthIncludeGPU: Bool {
        didSet { save(healthIncludeGPU, for: .healthIncludeGPU) }
    }
    @Published var healthIncludePower: Bool {
        didSet { save(healthIncludePower, for: .healthIncludePower) }
    }

    /// 组装供 `HealthScoreService.compute` 使用的维度开关。
    var healthDimensionToggles: HealthScoreService.DimensionToggles {
        HealthScoreService.DimensionToggles(
            cpu: healthIncludeCPU,
            memory: healthIncludeMemory,
            load: healthIncludeLoad,
            temperature: healthIncludeTemperature,
            gpu: healthIncludeGPU,
            power: healthIncludePower
        )
    }

    // MARK: - Accessibility

    /// 监控列表用颜色圆点指示等级（默认开）；关闭后回退到「低/中/高」文字。
    @Published var useColorIndicator: Bool {
        didSet { save(useColorIndicator, for: .useColorIndicator) }
    }

    /// Product theme preset. Cold-start default `.noir` (Ink Night / 墨夜).
    @Published var appTheme: AppTheme {
        didSet { save(appTheme.rawValue, for: .appTheme) }
    }

    // MARK: - Film Theme Appearance

    @Published var filmGrainEnabled: Bool {
        didSet { save(filmGrainEnabled, for: .filmGrainEnabled) }
    }
    @Published var filmLightFlow: Double {
        didSet {
            let safeValue = min(max(filmLightFlow, 0), 1)
            guard safeValue == filmLightFlow else {
                filmLightFlow = safeValue
                return
            }
            save(filmLightFlow, for: .filmLightFlow)
        }
    }

    // MARK: - Bar Theme Appearance

    @Published var barGrainEnabled: Bool {
        didSet { save(barGrainEnabled, for: .barGrainEnabled) }
    }
    @Published var barLightFlow: Double {
        didSet {
            let safeValue = min(max(barLightFlow, 0), 1)
            guard safeValue == barLightFlow else {
                barLightFlow = safeValue
                return
            }
            save(barLightFlow, for: .barLightFlow)
        }
    }

    // MARK: - Noir Theme Appearance

    @Published var noirGrainEnabled: Bool {
        didSet { save(noirGrainEnabled, for: .noirGrainEnabled) }
    }
    @Published var noirLightFlow: Double {
        didSet {
            let safeValue = min(max(noirLightFlow, 0), 1)
            guard safeValue == noirLightFlow else {
                noirLightFlow = safeValue
                return
            }
            save(noirLightFlow, for: .noirLightFlow)
        }
    }

    // MARK: - Other Settings

    /// 开机启动。真相源是系统登录项（`SMAppService`），不落 UserDefaults。
    /// `didSet` 注册/注销登录项；失败时回滚到系统实际状态，避免 UI 与登录项不一致。
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            do {
                try LaunchAtLoginService.setEnabled(launchAtLogin)
            } catch {
                isSyncingLaunchAtLogin = true
                launchAtLogin = LaunchAtLoginService.isEnabled
                isSyncingLaunchAtLogin = false
            }
        }
    }
    private var isSyncingLaunchAtLogin = false

    @Published var refreshRate: RefreshRate {
        didSet { save(refreshRate.rawValue, for: .refreshRate) }
    }
    @Published var temperatureUnit: TemperatureUnit {
        didSet { save(temperatureUnit.rawValue, for: .temperatureUnit) }
    }
    // MARK: - AI Usage Settings

    /// Keyed by `settings.aiMonitor.<id>.enabled`. Not a per-vendor `@Published` Bool.
    @Published private(set) var enabledAIProviders: Set<AIProvider> = []

    func isAIProviderEnabled(_ id: AIProvider) -> Bool { enabledAIProviders.contains(id) }

    func setAIProviderEnabled(_ id: AIProvider, _ enabled: Bool) {
        var next = enabledAIProviders
        if enabled { next.insert(id) } else { next.remove(id) }
        guard next != enabledAIProviders else { return }
        enabledAIProviders = next
        let key = Self.aiMonitorEnabledKey(for: id)
        defaults.set(enabled, forKey: key)
        DiagnosticLogService.record(category: "settings", action: "changed", fields: ["key": key, "value": String(enabled)])
    }
    /// 自动续期 5h 窗口（warmup）。默认关闭（opt-in），仅在对应 provider 监控开启时才有意义。
    /// 开 → `UsageWarmupManager` 定时发一条 headless 消息把窗口起点挪进工作时段；关 → 立即停。
    /// Gemini 无对应开关（每日 quota，非滚动窗口）。
    @Published var autoRefreshClaudeEnabled: Bool {
        didSet { save(autoRefreshClaudeEnabled, for: .autoRefreshClaude) }
    }
    @Published var autoRefreshCodexEnabled: Bool {
        didSet { save(autoRefreshCodexEnabled, for: .autoRefreshCodex) }
    }

    @Published var appLanguage: AppLanguage {
        didSet {
            save(appLanguage.rawValue, for: .appLanguage)
            Task { @MainActor in
                LocalizationManager.shared.setLanguage(appLanguage)
            }
        }
    }

    // MARK: - Network / Exit Node Settings

    /// 出口节点探测开关。默认关闭，需用户主动开启。
    @Published var exitNodeDetectionEnabled: Bool {
        didSet { save(exitNodeDetectionEnabled, for: .exitNodeDetectionEnabled) }
    }
    /// 出口探测使用的 geo-IP 服务。
    @Published var exitNodeProvider: ExitNodeProvider {
        didSet { save(exitNodeProvider.rawValue, for: .exitNodeProvider) }
    }

    // MARK: - Software Update Settings

    /// 启动时与定时自动检查更新。默认关闭。
    @Published var autoCheckUpdates: Bool {
        didSet { save(autoCheckUpdates, for: .autoCheckUpdates) }
    }
    /// 更新通道是否纳入 GitHub prerelease（beta）。默认关闭：只收正式版。
    /// 开启后自动检查与手动「检查更新」均会接受预发布版本。
    @Published var includeBetaUpdates: Bool {
        didSet { save(includeBetaUpdates, for: .includeBetaUpdates) }
    }
    /// 独立输入设备滚动方向翻转：仅传统鼠标滚轮垂直反向，触控板保持自然滚动。
    @Published var scrollReverseEnabled: Bool {
        didSet { save(scrollReverseEnabled, for: .scrollReverseEnabled) }
    }
    /// 窗口管理总开关：单一开关同时驱动菜单栏图标、贴靠快捷键、标题栏滑动手势、拖动吸附与悬浮岛。
    /// 默认关闭（opt-in），需辅助功能权限移动其他 App 窗口。
    @Published var windowManagementEnabled: Bool {
        didSet { save(windowManagementEnabled, for: .windowManagementEnabled) }
    }
    /// 窗口管理的全部子配置（间距、触发区、悬浮岛、排除列表、快捷键、布局）。
    /// 作为单个 JSON 值存储：设置面一次只增加一个键，重置窗口管理也只是删一个键。
    @Published var windowSnap: SnapConfiguration {
        didSet { save(windowSnap.json, for: .windowSnap) }
    }
    /// 默认输入法：默认关闭（opt-in）。开 → 每个 App 激活后把输入源拉回 `defaultInputSourceID`；
    /// 关 → 立即移除激活观察者，不再触碰输入源。
    @Published var defaultInputSourceEnabled: Bool {
        didSet { save(defaultInputSourceEnabled, for: .defaultInputSourceEnabled) }
    }
    /// 默认输入法的 TIS input source ID（如 `com.tencent.inputmethod.wetype.pinyin`）。
    /// 未选择时为 nil：开关开着也视为未运行，避免误切到用户没挑过的输入源。
    @Published var defaultInputSourceID: String? {
        didSet { save(defaultInputSourceID, for: .defaultInputSourceID) }
    }
    /// 显示器硬件亮度控制：默认关闭。开启后才枚举显示器、注册拓扑观察并访问 DDC 总线。
    @Published var displayBrightnessControlEnabled: Bool {
        didSet { save(displayBrightnessControlEnabled, for: .displayBrightnessControlEnabled) }
    }
    /// 水平滚动方向翻转：与垂直独立，同样仅作用于传统鼠标滚轮。
    @Published var scrollReverseHorizontalEnabled: Bool {
        didSet { save(scrollReverseHorizontalEnabled, for: .scrollReverseHorizontalEnabled) }
    }
    /// 滚动步长倍率：缩放鼠标滚轮单次滚动的像素量，范围 0.25×–3×，默认 1×（不改变）。
    @Published var scrollStepMultiplier: Double {
        didSet { save(scrollStepMultiplier, for: .scrollStepMultiplier) }
    }
    /// 关闭鼠标滚轮加速度：开启后每次滚轮事件滚动固定 `scrollLines` 行，滚动量不再随转速放大。
    @Published var scrollDisableAcceleration: Bool {
        didSet { save(scrollDisableAcceleration, for: .scrollDisableAcceleration) }
    }
    /// 加速度关闭时每次滚轮事件滚动的行数（1–10，默认 3）。
    @Published var scrollLines: Int {
        didSet { save(scrollLines, for: .scrollLines) }
    }
    /// 触控板 / Magic Mouse 是否也参与方向反转（默认 false：仅传统鼠标滚轮）。
    @Published var scrollIncludeTrackpad: Bool {
        didSet { save(scrollIncludeTrackpad, for: .scrollIncludeTrackpad) }
    }
    /// Finder 右键菜单总开关：默认关闭（opt-in）。开 → 宿主注册 CFMessagePort、扩展出菜单；
    /// 关 → 端口注销、扩展不出菜单。值镜像写入 App Group 容器供沙盒扩展读取。
    @Published var finderMenuEnabled: Bool {
        didSet {
            save(finderMenuEnabled, for: .finderMenuEnabled)
            FinderMenuShared.setEnabled(finderMenuEnabled)
        }
    }
    /// 保持唤醒：默认关闭（opt-in）。开 → 阻止空闲息屏；插电且无外接屏时挂虚拟屏以支持合盖。
    @Published var keepAwakeEnabled: Bool {
        didSet { save(keepAwakeEnabled, for: .keepAwakeEnabled) }
    }
    /// 找到我的鼠标：默认关闭（opt-in，需辅助功能权限）。开 → 双按所选快捷键全屏聚光指针。
    @Published var findMouseEnabled: Bool {
        didSet { save(findMouseEnabled, for: .findMouseEnabled) }
    }
    @Published var findMouseTriggerKey: FindMouseTriggerKey {
        didSet { save(findMouseTriggerKey.rawValue, for: .findMouseTriggerKey) }
    }
    /// 演示指针配色：只换图集，不影响三按手势的开关语义。
    @Published var presentationCursorStyle: PresentationCursorStyle {
        didSet { save(presentationCursorStyle.rawValue, for: .presentationCursorStyle) }
    }
    /// 在指针处打开清理页：默认关闭（opt-in）。Carbon 全局热键，不需要辅助功能权限。
    @Published var cleanupPanelHotKeyEnabled: Bool {
        didSet { save(cleanupPanelHotKeyEnabled, for: .cleanupPanelHotKeyEnabled) }
    }
    @Published var cleanupPanelHotKey: PanelHotKey {
        didSet { save(cleanupPanelHotKey.rawValue, for: .cleanupPanelHotKey) }
    }
    /// 高级功能激活码（离线 Ed25519 签名载荷）。原始码落 UserDefaults，启动时由
    /// `LicenseManager` 重新校验；签名载荷非机密，与「不绑定机器」策略一致。
    @Published var activationCode: String? {
        didSet { save(activationCode, for: .activationCode) }
    }
    /// 赠送期用户及收费前老用户的永久 Pro 资格。标记一旦为 true，收费后仍保持有效。
    @Published private(set) var isGrandfathered: Bool
    /// 用户「忽略此版本」记录的 tag，自动检查时跳过该版本（手动检查仍会提示）。
    @Published var lastIgnoredVersion: String {
        didSet { save(lastIgnoredVersion, for: .lastIgnoredVersion) }
    }

    // MARK: - Singleton

    static let shared = SettingsManager()

    // MARK: - Enums

    enum RefreshRate: String, CaseIterable {
        case low       // 5 seconds
        case medium // 2 seconds
        case high     // 1 second

        var interval: TimeInterval {
            switch self {
            case .low: return 5.0
            case .medium: return 2.0
            case .high: return 1.0
            }
        }

        var displayName: String {
            switch self {
            case .low: return "refreshRate.low".localized
            case .medium: return "refreshRate.medium".localized
            case .high: return "refreshRate.high".localized
            }
        }
    }

    enum TemperatureUnit: String, CaseIterable {
        case celsius
        case fahrenheit

        var displayName: String {
            switch self {
            case .celsius: return "°C"
            case .fahrenheit: return "°F"
            }
        }

        func format(_ celsius: Double) -> String {
            switch self {
            case .celsius:
                return String(format: "%.0f°C", celsius)
            case .fahrenheit:
                let fahrenheit = celsius * 9 / 5 + 32
                return String(format: "%.0f°F", fahrenheit)
            }
        }
    }

    // MARK: - Keys

    private enum Key: String {
        case showLogo = "settings.showLogo"
        case showCPU = "settings.showCPU"
        case showGPU = "settings.showGPU"
        case showMemory = "settings.showMemory"
        case showDisk = "settings.showDisk"
        case showNetwork = "settings.showNetwork"
        case showFan = "settings.showFan"
        case showBattery = "settings.showBattery"
        case showHealth = "settings.showHealth"
        case healthIncludeCPU = "settings.healthIncludeCPU"
        case healthIncludeMemory = "settings.healthIncludeMemory"
        case healthIncludeLoad = "settings.healthIncludeLoad"
        case healthIncludeTemperature = "settings.healthIncludeTemperature"
        case healthIncludeGPU = "settings.healthIncludeGPU"
        case healthIncludePower = "settings.healthIncludePower"
        case useColorIndicator = "settings.useColorIndicator"
        case appTheme = "settings.appTheme"
        case filmGrainEnabled = "settings.filmGrainEnabled"
        case filmLightFlow = "settings.filmLightFlow"
        case barGrainEnabled = "settings.barGrainEnabled"
        case barLightFlow = "settings.barLightFlow"
        case noirGrainEnabled = "settings.noirGrainEnabled"
        case noirLightFlow = "settings.noirLightFlow"
        case refreshRate = "settings.refreshRate"
        case temperatureUnit = "settings.temperatureUnit"
        case appLanguage = "settings.appLanguage"
        case exitNodeDetectionEnabled = "settings.exitNodeDetectionEnabled"
        case exitNodeProvider = "settings.exitNodeProvider"
        case autoRefreshClaude = "settings.autoRefreshClaude"
        case autoRefreshCodex = "settings.autoRefreshCodex"
        case autoCheckUpdates = "settings.autoCheckUpdates"
        case includeBetaUpdates = "settings.includeBetaUpdates"
        case lastIgnoredVersion = "settings.lastIgnoredVersion"
        case scrollReverseEnabled = "settings.scrollReverseEnabled"
        case windowManagementEnabled = "settings.windowManagementEnabled"
        case windowSnap = "settings.windowSnap"
        case defaultInputSourceEnabled = "settings.defaultInputSourceEnabled"
        case defaultInputSourceID = "settings.defaultInputSourceID"
        case displayBrightnessControlEnabled = "settings.displayBrightnessControlEnabled"
        case finderMenuEnabled = "settings.finderMenuEnabled"
        case scrollReverseHorizontalEnabled = "settings.scrollReverseHorizontalEnabled"
        case scrollStepMultiplier = "settings.scrollStepMultiplier"
        case scrollDisableAcceleration = "settings.scrollDisableAcceleration"
        case scrollLines = "settings.scrollLines"
        case scrollIncludeTrackpad = "settings.scrollIncludeTrackpad"
        case keepAwakeEnabled = "settings.keepAwakeEnabled"
        case findMouseEnabled = "settings.findMouseEnabled"
        case findMouseTriggerKey = "settings.findMouseTriggerKey"
        case presentationCursorStyle = "settings.presentationCursorStyle"
        case cleanupPanelHotKeyEnabled = "settings.cleanupPanelHotKeyEnabled"
        case cleanupPanelHotKey = "settings.cleanupPanelHotKey"
        case activationCode = "settings.activationCode"
        case isGrandfathered = "settings.grandfathered"
    }

    // MARK: - Init

    /// `defaults` is injectable so tests can exercise persistence in an isolated suite.
    /// Production uses `.standard` through the process-lifetime singleton.
    init(defaults: UserDefaults = .standard, proGiftEnabled: Bool = AppConfig.proGiftEnabled) {
        self.defaults = defaults

        // 赠送期开启时，无条件把永久 Pro 资格写为 true（也修正试运行版本曾写入的 false）。
        // 收费后关闭开关：已获赠的 true 永久保留；没有标记但存在历史偏好的升级用户仍
        // 获得资格；真正的收费后全新安装才写入 false。边界由发布版本决定，不依赖系统日期。
        let storedGift = defaults.object(forKey: Key.isGrandfathered.rawValue) as? Bool
        let hasHistoricalSettings = defaults.dictionaryRepresentation().keys.contains { key in
            key.hasPrefix("settings.")
                && key != Key.activationCode.rawValue
                && key != Key.isGrandfathered.rawValue
        }
        let hasPermanentPro = proGiftEnabled || storedGift == true || (storedGift == nil && hasHistoricalSettings)
        isGrandfathered = hasPermanentPro
        defaults.set(hasPermanentPro, forKey: Key.isGrandfathered.rawValue)

        // Status bar items - default all to true except disk/fan
        showLogo = defaults.object(forKey: Key.showLogo.rawValue) as? Bool ?? true
        showCPU = defaults.object(forKey: Key.showCPU.rawValue) as? Bool ?? true
        showGPU = defaults.object(forKey: Key.showGPU.rawValue) as? Bool ?? true
        showMemory = defaults.object(forKey: Key.showMemory.rawValue) as? Bool ?? true
        showDisk = defaults.object(forKey: Key.showDisk.rawValue) as? Bool ?? false
        showNetwork = defaults.object(forKey: Key.showNetwork.rawValue) as? Bool ?? false
        showFan = defaults.object(forKey: Key.showFan.rawValue) as? Bool ?? false
        // 电池：菜单栏默认关闭（沿用 disk/fan 的 toggle 模式）。
        showBattery = defaults.object(forKey: Key.showBattery.rawValue) as? Bool ?? false
        // 健康分：总门面默认关闭，避免改变现有菜单栏宽度。
        showHealth = defaults.object(forKey: Key.showHealth.rawValue) as? Bool ?? false

        // 健康分维度：默认全部参与计算（含 GPU）。
        healthIncludeCPU = defaults.object(forKey: Key.healthIncludeCPU.rawValue) as? Bool ?? true
        healthIncludeMemory = defaults.object(forKey: Key.healthIncludeMemory.rawValue) as? Bool ?? true
        healthIncludeLoad = defaults.object(forKey: Key.healthIncludeLoad.rawValue) as? Bool ?? true
        healthIncludeTemperature = defaults.object(forKey: Key.healthIncludeTemperature.rawValue) as? Bool ?? true
        healthIncludeGPU = defaults.object(forKey: Key.healthIncludeGPU.rawValue) as? Bool ?? true
        healthIncludePower = defaults.object(forKey: Key.healthIncludePower.rawValue) as? Bool ?? true

        // 颜色指示器：默认开启（关闭则回退到文字等级）。
        useColorIndicator = defaults.object(forKey: Key.useColorIndicator.rawValue) as? Bool ?? true
        // 主题：默认 noir（展示名「墨夜」）。未知旧键回落到 noir。
        appTheme = AppTheme.resolve(stored: defaults.string(forKey: Key.appTheme.rawValue))
        filmGrainEnabled = defaults.object(forKey: Key.filmGrainEnabled.rawValue) as? Bool ?? true
        let storedFlow = defaults.object(forKey: Key.filmLightFlow.rawValue) as? Double ?? 0.4
        filmLightFlow = min(max(storedFlow, 0), 1)
        barGrainEnabled = defaults.object(forKey: Key.barGrainEnabled.rawValue) as? Bool ?? true
        let storedBarFlow = defaults.object(forKey: Key.barLightFlow.rawValue) as? Double ?? 0.4
        barLightFlow = min(max(storedBarFlow, 0), 1)
        noirGrainEnabled = defaults.object(forKey: Key.noirGrainEnabled.rawValue) as? Bool ?? true
        let storedNoirFlow = defaults.object(forKey: Key.noirLightFlow.rawValue) as? Double ?? 0.4
        noirLightFlow = min(max(storedNoirFlow, 0), 1)
        // 开机启动：以系统登录项注册状态为唯一真相源。
        launchAtLogin = LaunchAtLoginService.isEnabled

        // Other settings
        let refreshRateStr = defaults.string(forKey: Key.refreshRate.rawValue) ?? RefreshRate.medium.rawValue
        refreshRate = RefreshRate(rawValue: refreshRateStr) ?? .medium

        let tempUnitStr = defaults.string(forKey: Key.temperatureUnit.rawValue) ?? TemperatureUnit.celsius.rawValue
        temperatureUnit = TemperatureUnit(rawValue: tempUnitStr) ?? .celsius

        let langStr = defaults.string(forKey: Key.appLanguage.rawValue) ?? AppLanguage.system.rawValue
        appLanguage = AppLanguage(rawValue: langStr) ?? .system

        // 出口探测默认关闭，provider 默认 ip.sb。
        exitNodeDetectionEnabled = defaults.object(forKey: Key.exitNodeDetectionEnabled.rawValue) as? Bool ?? false
        let providerStr = defaults.string(forKey: Key.exitNodeProvider.rawValue) ?? ExitNodeProvider.ipsb.rawValue
        exitNodeProvider = ExitNodeProvider(rawValue: providerStr) ?? .ipsb

        // AI usage monitoring - opt-in, default off. Keyed by provider id.
        enabledAIProviders = Self.migrateAndReadEnabledAIProviders(from: defaults)
        // 自动续期窗口：默认关闭（opt-in）。
        autoRefreshClaudeEnabled = defaults.object(forKey: Key.autoRefreshClaude.rawValue) as? Bool ?? false
        autoRefreshCodexEnabled = defaults.object(forKey: Key.autoRefreshCodex.rawValue) as? Bool ?? false

        // 自动检查更新：默认关闭。
        autoCheckUpdates = defaults.object(forKey: Key.autoCheckUpdates.rawValue) as? Bool ?? false
        // Beta 尝鲜：默认关闭，正式用户只收稳定版。
        includeBetaUpdates = defaults.object(forKey: Key.includeBetaUpdates.rawValue) as? Bool ?? false
        // 滚动方向翻转：默认关闭（opt-in）。
        scrollReverseEnabled = defaults.object(forKey: Key.scrollReverseEnabled.rawValue) as? Bool ?? false
        // 窗口管理总开关：默认关闭（opt-in），不迁移旧的快捷键/标题栏手势子开关。
        windowManagementEnabled = defaults.object(forKey: Key.windowManagementEnabled.rawValue) as? Bool ?? false
        windowSnap = defaults.string(forKey: Key.windowSnap.rawValue)
            .flatMap(SnapConfiguration.init(json:)) ?? .default
        // 默认输入法：默认关闭（opt-in）。冷启动不注册 NSWorkspace 激活观察者、不读输入源。
        defaultInputSourceEnabled = defaults.object(forKey: Key.defaultInputSourceEnabled.rawValue) as? Bool ?? false
        defaultInputSourceID = defaults.string(forKey: Key.defaultInputSourceID.rawValue)
        // 显示器 DDC 硬件亮度：默认关闭（opt-in），冷启动不枚举、不探测、不访问 I²C。
        displayBrightnessControlEnabled =
            defaults.object(forKey: Key.displayBrightnessControlEnabled.rawValue) as? Bool ?? false
        // Finder 右键菜单：默认关闭（opt-in）。
        finderMenuEnabled = defaults.object(forKey: Key.finderMenuEnabled.rawValue) as? Bool ?? false
        scrollReverseHorizontalEnabled =
            defaults.object(forKey: Key.scrollReverseHorizontalEnabled.rawValue) as? Bool ?? false
        // 步长倍率：默认 1×；夹取到 0.25–3× 防御历史/异常值。
        let storedMultiplier = defaults.object(forKey: Key.scrollStepMultiplier.rawValue) as? Double ?? 1.0
        scrollStepMultiplier = min(max(storedMultiplier, 0.25), 3.0)
        scrollDisableAcceleration = defaults.object(forKey: Key.scrollDisableAcceleration.rawValue) as? Bool ?? false
        let storedScrollLines = defaults.object(forKey: Key.scrollLines.rawValue) as? Int ?? 3
        scrollLines = min(max(storedScrollLines, 1), 10)
        scrollIncludeTrackpad = defaults.object(forKey: Key.scrollIncludeTrackpad.rawValue) as? Bool ?? false
        // 保持唤醒：默认关闭（opt-in）。
        keepAwakeEnabled = defaults.object(forKey: Key.keepAwakeEnabled.rawValue) as? Bool ?? false
        // 找到我的鼠标：默认关闭（opt-in）；触发快捷键默认左 Control。
        findMouseEnabled = defaults.object(forKey: Key.findMouseEnabled.rawValue) as? Bool ?? false
        findMouseTriggerKey = defaults.string(forKey: Key.findMouseTriggerKey.rawValue)
            .flatMap(FindMouseTriggerKey.init(rawValue:)) ?? .leftControl
        // 演示指针配色：未知/缺失值回落到出厂配色。
        presentationCursorStyle = defaults.string(forKey: Key.presentationCursorStyle.rawValue)
            .flatMap(PresentationCursorStyle.init(rawValue:)) ?? .shippedDefault
        cleanupPanelHotKeyEnabled = defaults.object(forKey: Key.cleanupPanelHotKeyEnabled.rawValue) as? Bool ?? false
        cleanupPanelHotKey = defaults.string(forKey: Key.cleanupPanelHotKey.rawValue)
            .flatMap(PanelHotKey.init(rawValue:)) ?? .default
        // 激活码：冷启动默认未激活（无高级功能解锁）。
        activationCode = defaults.string(forKey: Key.activationCode.rawValue)
        lastIgnoredVersion = defaults.string(forKey: Key.lastIgnoredVersion.rawValue) ?? ""

        // 所有存储属性初始化完成后，把 Finder 菜单开关初值镜像进 App Group 容器，
        // 确保沙盒扩展冷启动即读到正确状态。
        FinderMenuShared.setEnabled(finderMenuEnabled)
    }

    // MARK: - Validation

    /// Returns true if at least one status bar item is enabled
    var hasAtLeastOneItem: Bool {
        showLogo || showCPU || showGPU || showMemory || showDisk || showNetwork || showFan || showBattery || showHealth
    }

    /// Ensures at least one item is shown; if all are off, enable CPU
    func ensureAtLeastOneItem() {
        if !hasAtLeastOneItem {
            showCPU = true
        }
    }

    func exportDiagnosticReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = DiagnosticReportService.suggestedFilename()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let settings = self.diagnosticSettingsSnapshot()
            Task { @MainActor in
                do {
                    let reportURL = try await DiagnosticReportService.shared.createReport(
                        at: url,
                        settings: settings
                    )
                    NSWorkspace.shared.activateFileViewerSelecting([reportURL])
                } catch {
                    let nsError = error as NSError
                    DiagnosticLogService.record(
                        level: .error,
                        category: "diagnostics",
                        action: "exportFailed",
                        fields: [
                            "errorDomain": nsError.domain,
                            "errorCode": String(nsError.code)
                        ]
                    )
                    let alert = NSAlert()
                    alert.messageText = "settings.diagnosticReport.failed".localized
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "settings.ok".localized)
                    alert.runModal()
                }
            }
        }
    }

    private func diagnosticSettingsSnapshot() -> [String: String] {
        [
            "theme": appTheme.rawValue,
            "refreshRate": refreshRate.rawValue,
            "temperatureUnit": temperatureUnit.rawValue,
            "language": appLanguage.rawValue,
            "exitNodeDetectionEnabled": String(exitNodeDetectionEnabled),
            "aiEnabled": enabledAIProviders.map(\.rawValue).sorted().joined(separator: ","),
            "windowManagementEnabled": String(windowManagementEnabled),
            "snapMargins": String(format: "%.0f/%.0f", windowSnap.margins.outer, windowSnap.margins.inner),
            "snapTopEdgeMode": windowSnap.zones.topEdgeMode.rawValue,
            "snapShortcuts": String(windowSnap.shortcuts.count),
            "snapExclusions": String(windowSnap.exclusions.count),
            "displayBrightnessControlEnabled": String(displayBrightnessControlEnabled),
            "finderMenuEnabled": String(finderMenuEnabled),
            "scrollReverseEnabled": String(scrollReverseEnabled),
            "keepAwakeEnabled": String(keepAwakeEnabled),
            "findMouseEnabled": String(findMouseEnabled),
            "presentationCursorStyle": presentationCursorStyle.rawValue
        ]
    }

    /// True when `value` is an optional in its `.none` state.
    static func isNilOptional<T>(_ value: T) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }
}

// MARK: - Persistence

/// Preference writes and their journal projection live in an extension so the class body
/// stays under the lint ceiling. `private` members are visible to a same-file extension.
private extension SettingsManager {
    private func save<T>(_ value: T, for key: Key) {
        // Optional values: set(_:forKey:) boxes a nil optional as NSNull, which is not a
        // property-list type and throws NSInvalidArgumentException — remove the key instead.
        if Self.isNilOptional(value) {
            defaults.removeObject(forKey: key.rawValue)
        } else {
            defaults.set(value, forKey: key.rawValue)
        }
        let loggedValue = Self.loggedValue(for: key, value: value)
        DiagnosticLogService.record(
            category: "settings",
            action: "changed",
            fields: ["key": key.rawValue, "value": loggedValue]
        )
        // 延迟执行以避免在视图更新过程中修改状态
        Task { @MainActor in
            ensureAtLeastOneItem()
        }
    }

    /// What goes into the diagnostic journal for a preference change.
    ///
    /// The window-snap configuration is a JSON blob that changes on every drag of a gap slider;
    /// logging it verbatim would flood the journal with kilobytes of base64-free JSON per second and
    /// make the journal useless for the thing it exists for. It is summarised instead.
    private static func loggedValue<T>(for key: Key, value: T) -> String {
        switch key {
        case .activationCode:
            return "<redacted>"
        case .windowSnap:
            guard let configuration = SnapConfiguration(json: value as? String ?? "") else {
                return "<unreadable>"
            }
            return String(
                format: "margins=%.0f/%.0f zones=%d island=%d shortcuts=%d layouts=%d exclusions=%d",
                configuration.margins.outer,
                configuration.margins.inner,
                configuration.zones.isActive ? 1 : 0,
                configuration.islandLayoutIDs.count,
                configuration.shortcuts.count,
                configuration.customLayouts.count,
                configuration.exclusions.count
            )
        default:
            return String(describing: value)
        }
    }
}
