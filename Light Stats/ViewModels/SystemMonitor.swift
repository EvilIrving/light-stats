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
    let topCPUProcesses: [TopProcess]
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
                 exitDetectionEnabled: Bool,
                 exitProvider: ExitNodeProvider,
                 exitCacheTTL: TimeInterval) async -> SystemSnapshot {
        let cpuInfo = await getCPUInfo()
        let networkInfo = await getNetworkInfo()

        // 出口探测可能走网络，尽早起 async let 让它与其它采集并行；关闭时直接为 nil。
        async let topProcesses = ProcessStats.getTopCPUProcesses(count: topProcessCount)
        async let exitNodeResult: ExitNode? = exitDetectionEnabled
            ? exitNodeService.fetch(provider: exitProvider, cacheTTL: exitCacheTTL)
            : nil

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

        // 本地代理探测与主接口 IP 都是 nonisolated 纯 syscall，在采集 actor 上同步执行（不占主线程）。
        let proxyConfig = ProxyDetector.shared.currentProxyConfig()
        let primaryIP = networkInfo.primaryInterface()?.ip
        let exitNode = await exitNodeResult
        let route = classifyRoute(proxy: proxyConfig, exit: exitNode)

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

    // MARK: - Private Methods

    private func requestUpdate() {
        pendingUpdate = true

        guard updateTask == nil else { return }
        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while self.pendingUpdate && !Task.isCancelled {
                self.pendingUpdate = false
                let settings = SettingsManager.shared
                let snapshot = await self.sampler.collect(
                    topProcessCount: AppConfig.topCPUProcessCount,
                    exitDetectionEnabled: settings.exitNodeDetectionEnabled,
                    exitProvider: settings.exitNodeProvider,
                    exitCacheTTL: AppConfig.exitNodeCacheTTL
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
        topCPUProcesses = snapshot.topCPUProcesses
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
        proxyConfig = snapshot.proxyConfig
        primaryIP = snapshot.primaryIP
        exitNode = snapshot.exitNode
        route = snapshot.route
    }
}
