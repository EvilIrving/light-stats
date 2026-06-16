//
//  SystemMonitor.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation
import Combine

private struct SystemSnapshot {
    let cpuUsage: Double
    let cpuUserUsage: Double
    let cpuSystemUsage: Double
    let coreUsages: [Double]
    let coreTopology: CoreTopology
    let loadAverage: LoadAverage
    /// nil 表示本轮未采集进程榜（弹窗关闭或未到节流间隔），应保留上一次的值。
    let topCPUProcesses: [TopProcess]?
    let gpuUsage: Double?
    let memoryUsage: Double
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let diskUsed: UInt64
    let diskTotal: UInt64
    let diskAvailable: UInt64
    let networkUpload: Double
    let networkDownload: Double
    let cpuTemperature: Double?
    let fanSpeed: Int?
    let health: HealthScore
    // Phase 2: 电池/功耗 + 磁盘 IO
    let battery: BatteryInfo
    let diskIO: DiskIOStats
    // Phase 1: 网络 / 代理 / 出口节点
    let proxyConfig: ProxyConfig
    let primaryIP: String?
    let exitNode: ExitNode?
    let route: NetworkRoute
}

private actor MonitorSampler {
    private var cpuInfo: CPUInfo?
    private var networkInfo: NetworkInfo?
    private let exitNodeService = ExitNodeService()
    private let powerService = PowerService()
    private let diskIOService = DiskIOService()
    private let pageRateService = PageRateService()
    private var previousHealth: HealthScore?

    private func getCPUInfo() async -> CPUInfo {
        if let cpuInfo {
            return cpuInfo
        }
        let info = await MainActor.run { CPUInfo() }
        await info.warmup()
        cpuInfo = info
        return info
    }

    private func getNetworkInfo() async -> NetworkInfo {
        if let networkInfo {
            return networkInfo
        }
        let info = await MainActor.run { NetworkInfo() }
        networkInfo = info
        return info
    }

    func collect(topProcessCount: Int,
                 collectTopProcesses: Bool,
                 exitDetectionEnabled: Bool,
                 exitProvider: ExitNodeProvider,
                 exitCacheTTL: TimeInterval,
                 healthToggles: HealthScoreService.DimensionToggles) async -> SystemSnapshot {
        let cpuInfo = await getCPUInfo()
        let networkInfo = await getNetworkInfo()

        // 进程榜仅在弹窗打开且到达节流间隔时采集；否则跳过 `ps -A`，本轮置 nil 保留旧值。
        async let topProcesses: [TopProcess]? = collectTopProcesses
            ? ProcessStats.getTopCPUProcesses(count: topProcessCount)
            : nil
        // 出口探测可能走网络，尽早起 async let 让它与其它采集并行；关闭时直接为 nil。
        async let exitNodeResult: ExitNode? = exitDetectionEnabled
            ? exitNodeService.fetch(provider: exitProvider, cacheTTL: exitCacheTTL)
            : nil
        // 电池采集走 actor，与其它采集并行。
        async let batteryResult = powerService.current()

        let cpuUsage = await cpuInfo.getCPUUsage()
        let coreUsages = await cpuInfo.getPerCoreUsage()
        let loadAverage = await CPUInfo.getLoadAverage()
        let coreTopology = await cpuInfo.getCoreTopology()

        let memoryInfo = await MemoryInfo.getMemoryInfo()
        let diskInfo = await DiskInfo.getDiskInfo()
        let networkStats = await networkInfo.getNetworkStats()
        let gpuUsage = await GPUInfo.getGPUUsage()
        let cpuTemperature = await SMCInfo.getCPUTemperature()
        let fanSpeed = await SMCInfo.getFanSpeed()

        // 磁盘 IO 是 nonisolated 纯 syscall（差值法），在采集 actor 上同步执行。
        let diskIO = diskIOService.sample()
        // 换页速率同为差值法 syscall，与磁盘 IO 一致在采集 actor 上同步执行。
        let swapActivityMBs = pageRateService.sample()

        // 本地代理探测与主接口 IP 都是 nonisolated 纯 syscall，在采集 actor 上同步执行（不占主线程）。
        let proxyConfig = ProxyDetector.shared.currentProxyConfig()
        let primaryIP = networkInfo.primaryInterface()?.ip
        let exitNode = await exitNodeResult
        let route = classifyRoute(proxy: proxyConfig, exit: exitNode)
        let battery = await batteryResult
        let detailedMemory = MemoryInfo.getDetailedMemoryInfo()
        let rawHealth = HealthScoreService.compute(
            cpu: cpuUsage.total,
            memoryPressure: detailedMemory.pressureLevel,
            swapActivityMBs: swapActivityMBs,
            load1: loadAverage.load1,
            coreCount: coreTopology.totalCores,
            temp: cpuTemperature,
            thermalState: ProcessInfo.processInfo.thermalState,
            gpu: gpuUsage,
            batteryState: battery.state,
            batteryPercent: battery.percent,
            diskIO: diskIO.readMBs + diskIO.writeMBs,
            toggles: healthToggles
        )
        let health = HealthScoreService.smooth(current: rawHealth, previous: previousHealth)
        previousHealth = health

        return SystemSnapshot(
            cpuUsage: cpuUsage.total,
            cpuUserUsage: cpuUsage.user,
            cpuSystemUsage: cpuUsage.system,
            coreUsages: coreUsages,
            coreTopology: coreTopology,
            loadAverage: loadAverage,
            topCPUProcesses: await topProcesses,
            gpuUsage: gpuUsage,
            memoryUsage: memoryInfo.usagePercent,
            memoryUsed: memoryInfo.used,
            memoryTotal: memoryInfo.total,
            diskUsed: diskInfo.used,
            diskTotal: diskInfo.total,
            diskAvailable: diskInfo.available,
            networkUpload: networkStats.uploadSpeed,
            networkDownload: networkStats.downloadSpeed,
            cpuTemperature: cpuTemperature,
            fanSpeed: fanSpeed,
            health: health,
            battery: battery,
            diskIO: diskIO,
            proxyConfig: proxyConfig,
            primaryIP: primaryIP,
            exitNode: exitNode,
            route: route
        )
    }
}

/// Main class for monitoring system statistics
@MainActor
final class SystemMonitor: ObservableObject {

    // MARK: - Published Properties

    @Published var cpuUsage: Double = 0
    @Published var cpuUserUsage: Double = 0
    @Published var cpuSystemUsage: Double = 0
    @Published var coreUsages: [Double] = []
    
    // Core topology (Apple Silicon P/E cores)
    @Published var coreTopology: CoreTopology = .unknown
    
    // Load average (1, 5, 15 minutes)
    @Published var loadAverage: LoadAverage = .zero
    
    // Top CPU processes
    @Published var topCPUProcesses: [TopProcess] = []

    @Published var gpuUsage: Double? = nil

    @Published var memoryUsage: Double = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = 0

    @Published var diskUsed: UInt64 = 0
    @Published var diskTotal: UInt64 = 0
    @Published var diskAvailable: UInt64 = 0

    @Published var networkUpload: Double = 0  // bytes per second
    @Published var networkDownload: Double = 0  // bytes per second

    @Published var cpuTemperature: Double? = nil
    @Published var fanSpeed: Int? = nil
    @Published var health: HealthScore = .perfect

    // Phase 2: 电池/功耗 + 磁盘 IO
    @Published var battery: BatteryInfo = .noBattery
    @Published var diskIO: DiskIOStats = .zero

    // Phase 1: 网络 / 代理 / 出口节点
    @Published var proxyConfig: ProxyConfig = .none
    @Published var primaryIP: String? = nil
    @Published var exitNode: ExitNode? = nil
    @Published var route: NetworkRoute = .unknown

    // MARK: - Private Properties

    private var timer: Timer?
    private let sampler = MonitorSampler()
    private var updateTask: Task<Void, Never>?
    private var pendingUpdate = false

    /// 弹窗是否可见：进程榜只在弹窗内展示，关闭时不采集。
    private var popoverVisible = false
    /// 上次采集进程榜的时间，用于按 `topProcessRefreshInterval` 节流。
    private var lastTopProcessSampleAt: Date = .distantPast

    // MARK: - Singleton

    static let shared = SystemMonitor()

    private init() {
        // Warmup is done by MonitorSampler.
    }

    // MARK: - Public Methods

    func startMonitoring(interval: TimeInterval = 2.0) {
        stopMonitoring()

        requestUpdate()

        // Periodic updates
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.requestUpdate()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        updateTask?.cancel()
        updateTask = nil
        pendingUpdate = false
    }

    /// 弹窗显示/隐藏时由 AppDelegate 调用。打开时立即触发一次采样，
    /// 让进程榜尽快填充（重置节流计时，绕过 5 秒间隔）。
    func setPopoverVisible(_ visible: Bool) {
        guard popoverVisible != visible else { return }
        popoverVisible = visible
        if visible {
            lastTopProcessSampleAt = .distantPast
            requestUpdate()
        }
    }

    // MARK: - Private Methods

    private func requestUpdate() {
        pendingUpdate = true

        guard updateTask == nil else { return }
        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while self.pendingUpdate && !Task.isCancelled {
                self.pendingUpdate = false
                let settings = SettingsManager.shared
                let now = Date()
                // 进程榜：仅在弹窗可见且距上次采集≥节流间隔时采集。
                let collectTopProcesses = self.popoverVisible
                    && now.timeIntervalSince(self.lastTopProcessSampleAt) >= AppConfig.topProcessRefreshInterval
                if collectTopProcesses {
                    self.lastTopProcessSampleAt = now
                }
                let snapshot = await self.sampler.collect(
                    topProcessCount: AppConfig.topCPUProcessCount,
                    collectTopProcesses: collectTopProcesses,
                    exitDetectionEnabled: settings.exitNodeDetectionEnabled,
                    exitProvider: settings.exitNodeProvider,
                    exitCacheTTL: AppConfig.exitNodeCacheTTL,
                    healthToggles: settings.healthDimensionToggles
                )
                guard !Task.isCancelled else { break }
                self.applySnapshot(snapshot)
            }

            self.updateTask = nil
        }
    }

    private func applySnapshot(_ snapshot: SystemSnapshot) {
        objectWillChange.send()
        cpuUsage = snapshot.cpuUsage
        cpuUserUsage = snapshot.cpuUserUsage
        cpuSystemUsage = snapshot.cpuSystemUsage
        coreUsages = snapshot.coreUsages
        coreTopology = snapshot.coreTopology
        loadAverage = snapshot.loadAverage
        // nil 表示本轮未采集进程榜，保留上一次的值。
        if let topProcesses = snapshot.topCPUProcesses {
            topCPUProcesses = topProcesses
        }
        gpuUsage = snapshot.gpuUsage
        memoryUsage = snapshot.memoryUsage
        memoryUsed = snapshot.memoryUsed
        memoryTotal = snapshot.memoryTotal
        diskUsed = snapshot.diskUsed
        diskTotal = snapshot.diskTotal
        diskAvailable = snapshot.diskAvailable
        networkUpload = snapshot.networkUpload
        networkDownload = snapshot.networkDownload
        cpuTemperature = snapshot.cpuTemperature
        fanSpeed = snapshot.fanSpeed
        health = snapshot.health
        battery = snapshot.battery
        diskIO = snapshot.diskIO
        proxyConfig = snapshot.proxyConfig
        primaryIP = snapshot.primaryIP
        exitNode = snapshot.exitNode
        route = snapshot.route
    }
}
