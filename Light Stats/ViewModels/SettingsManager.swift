//
//  SettingsManager.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import AppKit
import Combine
import Foundation

/// 标 `nonisolated`：纯常量，供采集 actor / 服务直接读取（如电池缓存 TTL）。
nonisolated enum AppConfig {
    static let topCPUProcessCount: Int = 5
    static let topMemoryProcessCount: Int = 300
    static let topMemoryExactProcessLimit: Int = 80
    /// 进程榜采样间隔：进程榜仅在弹窗内展示，无需跟随主采样周期高频刷新，
    /// 单独节流以降低 `ps -A` 全进程表遍历的 CPU 开销。
    static let topProcessRefreshInterval: TimeInterval = 5.0
    static let appMemoryRefreshInterval: TimeInterval = 5.0
    /// 出口节点探测缓存有效期：TTL 内不重复发外部请求。
    static let exitNodeCacheTTL: TimeInterval = 60
    /// 电池慢变量（循环/健康/功耗/温度）缓存有效期：TTL 内不重复读 IORegistry。
    static let batteryHealthCacheTTL: TimeInterval = 30
    /// AI 用量刷新间隔固定为 2 分钟，降低令牌长时间闲置后失效的概率。
    static let aiUsageRefreshInterval: TimeInterval = 120
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
    var useFlatColors: Bool { get set }
    var appTheme: AppTheme { get set }
    var refreshRate: SettingsManager.RefreshRate { get set }
    var temperatureUnit: SettingsManager.TemperatureUnit { get set }
    var exitNodeDetectionEnabled: Bool { get set }
    var exitNodeProvider: ExitNodeProvider { get set }
    var autoCheckUpdates: Bool { get set }
    var includeBetaUpdates: Bool { get set }
    var windowManagementEnabled: Bool { get set }
    var finderMenuEnabled: Bool { get set }
}

@MainActor
final class SettingsManager: ObservableObject, SettingsManaging {

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
    /// 平缓色调：开启后除健康分外所有文本使用普通黑色，不再根据数值动态变色。
    @Published var useFlatColors: Bool {
        didSet { save(useFlatColors, for: .useFlatColors) }
    }

    /// Visual theme for popover / settings / about. Default `.glass` (Default / 默认).
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

    @Published var aiMonitorClaudeEnabled: Bool {
        didSet { save(aiMonitorClaudeEnabled, for: .aiMonitorClaude) }
    }
    @Published var aiMonitorCodexEnabled: Bool {
        didSet { save(aiMonitorCodexEnabled, for: .aiMonitorCodex) }
    }
    @Published var aiMonitorGeminiEnabled: Bool {
        didSet { save(aiMonitorGeminiEnabled, for: .aiMonitorGemini) }
    }
    @Published var aiUsageRefreshInterval: AIRefreshInterval {
        didSet { save(aiUsageRefreshInterval.rawValue, for: .aiUsageRefreshInterval) }
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

    /// 出口节点探测开关。隐私红线：默认关闭，需用户主动开启。
    @Published var exitNodeDetectionEnabled: Bool {
        didSet { save(exitNodeDetectionEnabled, for: .exitNodeDetectionEnabled) }
    }
    /// 出口探测使用的 geo-IP 服务。
    @Published var exitNodeProvider: ExitNodeProvider {
        didSet { save(exitNodeProvider.rawValue, for: .exitNodeProvider) }
    }

    // MARK: - Software Update Settings

    /// 启动时与定时自动检查更新。默认关闭（opt-in，零外发）。
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
    /// 窗口管理总开关：单一开关同时驱动菜单栏图标、贴靠快捷键、标题栏滑动手势。
    /// 默认关闭（opt-in），需辅助功能权限移动其他 App 窗口。开 = 图标 + 快捷键 + 手势全开；
    /// 关 = 三者一起消失、tap 全部 stop。
    @Published var windowManagementEnabled: Bool {
        didSet { save(windowManagementEnabled, for: .windowManagementEnabled) }
    }
    /// 水平滚动方向翻转：与垂直独立，同样仅作用于传统鼠标滚轮。
    @Published var scrollReverseHorizontalEnabled: Bool {
        didSet { save(scrollReverseHorizontalEnabled, for: .scrollReverseHorizontalEnabled) }
    }
    /// 滚动步长倍率：缩放鼠标滚轮单次滚动的像素量，范围 0.25×–3×，默认 1×（不改变）。
    @Published var scrollStepMultiplier: Double {
        didSet { save(scrollStepMultiplier, for: .scrollStepMultiplier) }
    }
    /// Finder 右键菜单总开关：默认关闭（opt-in）。开 → 宿主注册 CFMessagePort、扩展出菜单；
    /// 关 → 端口注销、扩展不出菜单。值镜像写入 App Group 容器供沙盒扩展读取。
    @Published var finderMenuEnabled: Bool {
        didSet {
            save(finderMenuEnabled, for: .finderMenuEnabled)
            FinderMenuShared.setEnabled(finderMenuEnabled)
        }
    }
    /// 保持唤醒（阻止息屏）：默认关闭（opt-in）。开 → 持有 IOPM 电源断言阻止显示器息屏；关 → 释放。
    @Published var keepAwakeEnabled: Bool {
        didSet { save(keepAwakeEnabled, for: .keepAwakeEnabled) }
    }
    /// 用户「忽略此版本」记录的 tag，自动检查时跳过该版本（手动检查仍会提示）。
    @Published var lastIgnoredVersion: String {
        didSet { save(lastIgnoredVersion, for: .lastIgnoredVersion) }
    }

    /// Local diagnostic JSONL verbosity: off / errors only / full (rate-limited samples).
    @Published var diagnosticLogLevel: DiagnosticLogLevel {
        didSet {
            DiagnosticLogService.setJournalMode(diagnosticLogLevel.journalMode)
            save(diagnosticLogLevel.rawValue, for: .diagnosticLogLevel)
        }
    }

    // MARK: - Singleton

    static let shared = SettingsManager()

    // MARK: - Enums

    enum DiagnosticLogLevel: String, CaseIterable {
        case off
        case errorsOnly
        case full

        var journalMode: DiagnosticLogService.JournalMode {
            switch self {
            case .off: return .off
            case .errorsOnly: return .errorsOnly
            case .full: return .full
            }
        }

        var displayName: String {
            switch self {
            case .off: return "settings.diagnosticLog.off".localized
            case .errorsOnly: return "settings.diagnosticLog.errorsOnly".localized
            case .full: return "settings.diagnosticLog.full".localized
            }
        }
    }

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

    enum AIRefreshInterval: String, CaseIterable {
        case m1
        case m2
        case m5
        case m15

        var interval: TimeInterval {
            switch self {
            case .m1: return 60
            case .m2: return 120
            case .m5: return 300
            case .m15: return 900
            }
        }

        var displayName: String {
            switch self {
            case .m1: return "1 min"
            case .m2: return "2 min"
            case .m5: return "5 min"
            case .m15: return "15 min"
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
        case useFlatColors = "settings.useFlatColors"
        case appTheme = "settings.appTheme"
        case filmGrainEnabled = "settings.filmGrainEnabled"
        case filmLightFlow = "settings.filmLightFlow"
        case noirGrainEnabled = "settings.noirGrainEnabled"
        case noirLightFlow = "settings.noirLightFlow"
        case refreshRate = "settings.refreshRate"
        case temperatureUnit = "settings.temperatureUnit"
        case appLanguage = "settings.appLanguage"
        case exitNodeDetectionEnabled = "settings.exitNodeDetectionEnabled"
        case exitNodeProvider = "settings.exitNodeProvider"
        case aiMonitorClaude = "settings.aiMonitorClaude"
        case aiMonitorCodex = "settings.aiMonitorCodex"
        case aiMonitorGemini = "settings.aiMonitorGemini"
        case aiUsageRefreshInterval = "settings.aiUsageRefreshInterval"
        case autoRefreshClaude = "settings.autoRefreshClaude"
        case autoRefreshCodex = "settings.autoRefreshCodex"
        case autoCheckUpdates = "settings.autoCheckUpdates"
        case includeBetaUpdates = "settings.includeBetaUpdates"
        case lastIgnoredVersion = "settings.lastIgnoredVersion"
        case scrollReverseEnabled = "settings.scrollReverseEnabled"
        case windowManagementEnabled = "settings.windowManagementEnabled"
        case finderMenuEnabled = "settings.finderMenuEnabled"
        case scrollReverseHorizontalEnabled = "settings.scrollReverseHorizontalEnabled"
        case scrollStepMultiplier = "settings.scrollStepMultiplier"
        case keepAwakeEnabled = "settings.keepAwakeEnabled"
        case diagnosticLogLevel = "settings.diagnosticLogLevel"
    }

    // MARK: - Init

    /// `defaults` is injectable purely so tests can assert the documented
    /// cold-start defaults against a clean `UserDefaults` suite. Production
    /// always uses `.standard` via the singleton; `save(_:for:)` still writes
    /// to `.standard`, so this initializer is read-only for non-standard suites.
    init(defaults: UserDefaults = .standard) {

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
        useFlatColors = defaults.object(forKey: Key.useFlatColors.rawValue) as? Bool ?? false
        // 主题：默认 glass（展示名「默认」）。aurora/paper 仍映射到 film（晒金）。
        appTheme = AppTheme.resolve(stored: defaults.string(forKey: Key.appTheme.rawValue))
        filmGrainEnabled = defaults.object(forKey: Key.filmGrainEnabled.rawValue) as? Bool ?? true
        let storedFlow = defaults.object(forKey: Key.filmLightFlow.rawValue) as? Double ?? 0.4
        filmLightFlow = min(max(storedFlow, 0), 1)
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

        // 出口探测默认关闭（隐私红线），provider 默认 ip.sb。
        exitNodeDetectionEnabled = defaults.object(forKey: Key.exitNodeDetectionEnabled.rawValue) as? Bool ?? false
        let providerStr = defaults.string(forKey: Key.exitNodeProvider.rawValue) ?? ExitNodeProvider.ipsb.rawValue
        exitNodeProvider = ExitNodeProvider(rawValue: providerStr) ?? .ipsb

        // AI usage monitoring - opt-in, default off
        aiMonitorClaudeEnabled = defaults.object(forKey: Key.aiMonitorClaude.rawValue) as? Bool ?? false
        aiMonitorCodexEnabled = defaults.object(forKey: Key.aiMonitorCodex.rawValue) as? Bool ?? false
        aiMonitorGeminiEnabled = defaults.object(forKey: Key.aiMonitorGemini.rawValue) as? Bool ?? false
        let aiIntervalStr = defaults.string(forKey: Key.aiUsageRefreshInterval.rawValue) ?? AIRefreshInterval.m2.rawValue
        aiUsageRefreshInterval = AIRefreshInterval(rawValue: aiIntervalStr) ?? .m2
        // 自动续期窗口：默认关闭（opt-in）。
        autoRefreshClaudeEnabled = defaults.object(forKey: Key.autoRefreshClaude.rawValue) as? Bool ?? false
        autoRefreshCodexEnabled = defaults.object(forKey: Key.autoRefreshCodex.rawValue) as? Bool ?? false

        // 自动检查更新：默认关闭（opt-in）。彻底零外发：默认形态不发起任何网络请求。
        autoCheckUpdates = defaults.object(forKey: Key.autoCheckUpdates.rawValue) as? Bool ?? false
        // Beta 尝鲜：默认关闭，正式用户只收稳定版。
        includeBetaUpdates = defaults.object(forKey: Key.includeBetaUpdates.rawValue) as? Bool ?? false
        // 滚动方向翻转：默认关闭（opt-in）。
        scrollReverseEnabled = defaults.object(forKey: Key.scrollReverseEnabled.rawValue) as? Bool ?? false
        // 窗口管理总开关：默认关闭（opt-in），不迁移旧的 magnet/titlebar 子开关。
        windowManagementEnabled = defaults.object(forKey: Key.windowManagementEnabled.rawValue) as? Bool ?? false
        // Finder 右键菜单：默认关闭（opt-in）。
        finderMenuEnabled = defaults.object(forKey: Key.finderMenuEnabled.rawValue) as? Bool ?? false
        scrollReverseHorizontalEnabled =
            defaults.object(forKey: Key.scrollReverseHorizontalEnabled.rawValue) as? Bool ?? false
        // 步长倍率：默认 1×；夹取到 0.25–3× 防御历史/异常值。
        let storedMultiplier = defaults.object(forKey: Key.scrollStepMultiplier.rawValue) as? Double ?? 1.0
        scrollStepMultiplier = min(max(storedMultiplier, 0.25), 3.0)
        // 保持唤醒：默认关闭（opt-in）。
        keepAwakeEnabled = defaults.object(forKey: Key.keepAwakeEnabled.rawValue) as? Bool ?? false
        lastIgnoredVersion = defaults.string(forKey: Key.lastIgnoredVersion.rawValue) ?? ""

        // 诊断日志：默认完整（含限速 sample）；关 / 仅错误可在设置中收窄。
        let logLevelStr = defaults.string(forKey: Key.diagnosticLogLevel.rawValue)
            ?? DiagnosticLogLevel.full.rawValue
        diagnosticLogLevel = DiagnosticLogLevel(rawValue: logLevelStr) ?? .full
        DiagnosticLogService.setJournalMode(diagnosticLogLevel.journalMode)

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

    func openDiagnosticLogs() {
        Task {
            await DiagnosticLogService.shared.flush()
            NSWorkspace.shared.open(DiagnosticLogService.diagnosticsDirectoryURL)
        }
    }

    // MARK: - Private

    private func save<T>(_ value: T, for key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
        DiagnosticLogService.record(
            category: "settings",
            action: "changed",
            fields: ["key": key.rawValue, "value": String(describing: value)]
        )
        // 延迟执行以避免在视图更新过程中修改状态
        Task { @MainActor in
            ensureAtLeastOneItem()
        }
    }
}
