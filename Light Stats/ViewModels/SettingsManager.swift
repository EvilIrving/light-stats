//
//  SettingsManager.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation
import Combine

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
    var refreshRate: SettingsManager.RefreshRate { get set }
    var temperatureUnit: SettingsManager.TemperatureUnit { get set }
    var networkSpeedUnit: SettingsManager.NetworkSpeedUnit { get set }
    var exitNodeDetectionEnabled: Bool { get set }
    var exitNodeProvider: ExitNodeProvider { get set }
    var autoCheckUpdates: Bool { get set }
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

    // MARK: - Other Settings

    @Published var refreshRate: RefreshRate {
        didSet { save(refreshRate.rawValue, for: .refreshRate) }
    }
    @Published var temperatureUnit: TemperatureUnit {
        didSet { save(temperatureUnit.rawValue, for: .temperatureUnit) }
    }
    @Published var networkSpeedUnit: NetworkSpeedUnit {
        didSet { save(networkSpeedUnit.rawValue, for: .networkSpeedUnit) }
    }
    
    // MARK: - AI Usage Settings

    @Published var aiMonitorClaudeEnabled: Bool {
        didSet { save(aiMonitorClaudeEnabled, for: .aiMonitorClaude) }
    }
    @Published var aiMonitorCodexEnabled: Bool {
        didSet { save(aiMonitorCodexEnabled, for: .aiMonitorCodex) }
    }
    @Published var aiUsageRefreshInterval: AIRefreshInterval {
        didSet { save(aiUsageRefreshInterval.rawValue, for: .aiUsageRefreshInterval) }
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

    /// 启动时与定时自动检查更新。默认开启；用户可在设置关闭。
    @Published var autoCheckUpdates: Bool {
        didSet { save(autoCheckUpdates, for: .autoCheckUpdates) }
    }
    /// 用户「忽略此版本」记录的 tag，自动检查时跳过该版本（手动检查仍会提示）。
    @Published var lastIgnoredVersion: String {
        didSet { save(lastIgnoredVersion, for: .lastIgnoredVersion) }
    }

    // MARK: - Singleton

    static let shared = SettingsManager()
    
    // MARK: - Enums
    
    enum RefreshRate: String, CaseIterable {
        case low = "low"       // 5 seconds
        case medium = "medium" // 2 seconds
        case high = "high"     // 1 second
        
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
        case celsius = "celsius"
        case fahrenheit = "fahrenheit"
        
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
        case m1 = "m1"
        case m2 = "m2"
        case m5 = "m5"
        case m15 = "m15"

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

    enum NetworkSpeedUnit: String, CaseIterable {
        case auto = "auto"
        case kbps = "kbps"
        case mbps = "mbps"
        
        var displayName: String {
            switch self {
            case .auto: return "networkSpeed.auto".localized
            case .kbps: return "KB/s"
            case .mbps: return "MB/s"
            }
        }
        
        func format(_ bytesPerSecond: Double) -> String {
            switch self {
            case .auto:
                return ByteFormatter.formatSpeed(bytesPerSecond)
            case .kbps:
                return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
            case .mbps:
                return String(format: "%.2f MB/s", bytesPerSecond / 1_000_000)
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
        case refreshRate = "settings.refreshRate"
        case temperatureUnit = "settings.temperatureUnit"
        case networkSpeedUnit = "settings.networkSpeedUnit"
        case appLanguage = "settings.appLanguage"
        case exitNodeDetectionEnabled = "settings.exitNodeDetectionEnabled"
        case exitNodeProvider = "settings.exitNodeProvider"
        case aiMonitorClaude = "settings.aiMonitorClaude"
        case aiMonitorCodex = "settings.aiMonitorCodex"
        case aiUsageRefreshInterval = "settings.aiUsageRefreshInterval"
        case autoCheckUpdates = "settings.autoCheckUpdates"
        case lastIgnoredVersion = "settings.lastIgnoredVersion"
    }
    
    // MARK: - Init
    
    private init() {
        let defaults = UserDefaults.standard
        
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

        // Other settings
        let refreshRateStr = defaults.string(forKey: Key.refreshRate.rawValue) ?? RefreshRate.medium.rawValue
        refreshRate = RefreshRate(rawValue: refreshRateStr) ?? .medium
        
        let tempUnitStr = defaults.string(forKey: Key.temperatureUnit.rawValue) ?? TemperatureUnit.celsius.rawValue
        temperatureUnit = TemperatureUnit(rawValue: tempUnitStr) ?? .celsius
        
        let netUnitStr = defaults.string(forKey: Key.networkSpeedUnit.rawValue) ?? NetworkSpeedUnit.auto.rawValue
        networkSpeedUnit = NetworkSpeedUnit(rawValue: netUnitStr) ?? .auto
        
        let langStr = defaults.string(forKey: Key.appLanguage.rawValue) ?? AppLanguage.system.rawValue
        appLanguage = AppLanguage(rawValue: langStr) ?? .system

        // 出口探测默认关闭（隐私红线），provider 默认 ip.sb。
        exitNodeDetectionEnabled = defaults.object(forKey: Key.exitNodeDetectionEnabled.rawValue) as? Bool ?? false
        let providerStr = defaults.string(forKey: Key.exitNodeProvider.rawValue) ?? ExitNodeProvider.ipsb.rawValue
        exitNodeProvider = ExitNodeProvider(rawValue: providerStr) ?? .ipsb

        // AI usage monitoring - opt-in, default off
        aiMonitorClaudeEnabled = defaults.object(forKey: Key.aiMonitorClaude.rawValue) as? Bool ?? false
        aiMonitorCodexEnabled = defaults.object(forKey: Key.aiMonitorCodex.rawValue) as? Bool ?? false
        let aiIntervalStr = defaults.string(forKey: Key.aiUsageRefreshInterval.rawValue) ?? AIRefreshInterval.m2.rawValue
        aiUsageRefreshInterval = AIRefreshInterval(rawValue: aiIntervalStr) ?? .m2

        // 自动检查更新：默认开启。
        autoCheckUpdates = defaults.object(forKey: Key.autoCheckUpdates.rawValue) as? Bool ?? true
        lastIgnoredVersion = defaults.string(forKey: Key.lastIgnoredVersion.rawValue) ?? ""
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
    
    // MARK: - Private
    
    private func save<T>(_ value: T, for key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
        // 延迟执行以避免在视图更新过程中修改状态
        Task { @MainActor in
            ensureAtLeastOneItem()
        }
    }
}
