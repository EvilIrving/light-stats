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
    let memoryPressure: MemoryPressureLevel
    let swapUsed: UInt64
    let swapActivityMBs: Double
    let diskUsed: UInt64
    let diskTotal: UInt64
    let diskAvailable: UInt64
    let networkUpload: Double
    let networkDownload: Double
    let cpuTemperature: Double?
    let thermalState: String
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
    let selfMonitoring: SelfMonitoringSample?
    let selfMonitoringSessionID: String?
}

/// 一个持久化时间桶。常规指标取桶内平均值，网络取峰值，避免漏掉短突发流量。
private struct MetricTrendAccumulator {
    let startedAt: Date
    private var lastSample: MetricTrendSample
    private var weightedDuration: TimeInterval = 0
    private var cpuWeightedTotal: Double = 0
    private var memoryWeightedTotal: Double = 0
    private var gpuWeightedTotal: Double = 0
    private var loadWeightedTotal: Double = 0
    private var networkUpPeak: Double
    private var networkDownPeak: Double

    init(sample: MetricTrendSample) {
        startedAt = sample.timestamp
        lastSample = sample
        networkUpPeak = sample.networkUp
        networkDownPeak = sample.networkDown
    }

    mutating func add(_ sample: MetricTrendSample) {
        let duration = sample.timestamp.timeIntervalSince(lastSample.timestamp)
        if duration > 0 {
            cpuWeightedTotal += (lastSample.cpu + sample.cpu) * 0.5 * duration
            memoryWeightedTotal += (lastSample.memory + sample.memory) * 0.5 * duration
            gpuWeightedTotal += (lastSample.gpu + sample.gpu) * 0.5 * duration
            loadWeightedTotal += (lastSample.load + sample.load) * 0.5 * duration
            weightedDuration += duration
        }
        lastSample = sample
        networkUpPeak = max(networkUpPeak, sample.networkUp)
        networkDownPeak = max(networkDownPeak, sample.networkDown)
    }

    func aggregatedSample(endingAt requestedEnd: Date? = nil) -> MetricTrendSample {
        let bucketEnd = startedAt.addingTimeInterval(MetricTrendStore.sampleInterval)
        let requestedEnd = requestedEnd ?? lastSample.timestamp
        let end = min(max(requestedEnd, lastSample.timestamp), bucketEnd)
        let trailingDuration = end.timeIntervalSince(lastSample.timestamp)
        let totalDuration = weightedDuration + trailingDuration
        let cpuTotal = cpuWeightedTotal + lastSample.cpu * trailingDuration
        let memoryTotal = memoryWeightedTotal + lastSample.memory * trailingDuration
        let gpuTotal = gpuWeightedTotal + lastSample.gpu * trailingDuration
        let loadTotal = loadWeightedTotal + lastSample.load * trailingDuration

        return MetricTrendSample(
            timestamp: startedAt,
            cpu: totalDuration > 0 ? cpuTotal / totalDuration : lastSample.cpu,
            memory: totalDuration > 0 ? memoryTotal / totalDuration : lastSample.memory,
            gpu: totalDuration > 0 ? gpuTotal / totalDuration : lastSample.gpu,
            load: totalDuration > 0 ? loadTotal / totalDuration : lastSample.load,
            networkUp: networkUpPeak,
            networkDown: networkDownPeak
        )
    }
}

private actor MonitorSampler {
    private var cpuInfo: CPUInfo?
    private var networkInfo: NetworkInfo?
    private let exitNodeService = ExitNodeService()
    private let powerService = PowerService()
    private let diskIOService = DiskIOService()
    private let pageRateService = PageRateService()
    private lazy var selfMonitoringService = SelfMonitoringService()
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
                 healthToggles: HealthScoreService.DimensionToggles,
                 selfMonitoringSessionID: String?) async -> SystemSnapshot {
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
        let thermalState = ProcessInfo.processInfo.thermalState
        let rawHealth = HealthScoreService.compute(
            cpu: cpuUsage.total,
            memoryPressure: detailedMemory.pressureLevel,
            swapActivityMBs: swapActivityMBs,
            load1: loadAverage.load1,
            coreCount: coreTopology.totalCores,
            temp: cpuTemperature,
            thermalState: thermalState,
            gpu: gpuUsage,
            batteryState: battery.state,
            batteryPercent: battery.percent,
            diskIO: diskIO.readMBs + diskIO.writeMBs,
            toggles: healthToggles
        )
        let health = HealthScoreService.smooth(current: rawHealth, previous: previousHealth)
        previousHealth = health
        let selfMonitoring: SelfMonitoringSample? = if let selfMonitoringSessionID {
            await selfMonitoringService.sample(sessionID: selfMonitoringSessionID)
        } else {
            nil
        }

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
            memoryPressure: detailedMemory.pressureLevel,
            swapUsed: detailedMemory.swapUsed,
            swapActivityMBs: swapActivityMBs,
            diskUsed: diskInfo.used,
            diskTotal: diskInfo.total,
            diskAvailable: diskInfo.available,
            networkUpload: networkStats.uploadSpeed,
            networkDownload: networkStats.downloadSpeed,
            cpuTemperature: cpuTemperature,
            thermalState: String(describing: thermalState),
            fanSpeed: fanSpeed,
            health: health,
            battery: battery,
            diskIO: diskIO,
            proxyConfig: proxyConfig,
            primaryIP: primaryIP,
            exitNode: exitNode,
            route: route,
            selfMonitoring: selfMonitoring,
            selfMonitoringSessionID: selfMonitoringSessionID
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

    @Published var gpuUsage: Double?

    @Published var memoryUsage: Double = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = 0

    @Published var diskUsed: UInt64 = 0
    @Published var diskTotal: UInt64 = 0
    @Published var diskAvailable: UInt64 = 0

    @Published var networkUpload: Double = 0  // bytes per second
    @Published var networkDownload: Double = 0  // bytes per second

    @Published var cpuTemperature: Double?
    @Published var fanSpeed: Int?
    @Published var health: HealthScore = .perfect

    /// 各指标最近一段时间的取值序列，供弹窗 sparkline 折线读取（只读）。
    @Published private(set) var trends: MetricTrends = .empty

    // Phase 2: 电池/功耗 + 磁盘 IO
    @Published var battery: BatteryInfo = .noBattery
    @Published var diskIO: DiskIOStats = .zero

    // Phase 1: 网络 / 代理 / 出口节点
    @Published var proxyConfig: ProxyConfig = .none
    @Published var primaryIP: String?
    @Published var exitNode: ExitNode?
    @Published var route: NetworkRoute = .unknown

    // MARK: - Private Properties

    private var timer: Timer?
    private let sampler = MonitorSampler()
    private let trendStore = MetricTrendStore()
    private var updateTask: Task<Void, Never>?
    private var trendRestoreTask: Task<Void, Never>?
    private var updateGeneration: UInt = 0
    private var pendingUpdate = false

    // 趋势历史：时间戳随绘图值一起保留，唤醒后可立即裁掉三小时外的陈旧数据。
    private var trendSamples: [MetricTrendSample] = []
    private var trendAccumulator: MetricTrendAccumulator?
    private var lastTrendWriteAt: Date?
    private var hasRestoredTrendHistory = false

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

        if hasRestoredTrendHistory {
            requestUpdate()
        } else {
            restoreTrendHistory()
        }

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
        updateGeneration &+= 1
        updateTask?.cancel()
        updateTask = nil
        trendRestoreTask?.cancel()
        trendRestoreTask = nil
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

        guard hasRestoredTrendHistory else { return }
        guard updateTask == nil else { return }
        let generation = updateGeneration
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
                    healthToggles: settings.healthDimensionToggles,
                    selfMonitoringSessionID: PerformanceRecordingManager.shared.sessionIDForCapture(at: now)
                )
                guard !Task.isCancelled else { break }
                await self.applySnapshot(snapshot)
            }

            guard self.updateGeneration == generation else { return }
            self.updateTask = nil
        }
    }

    private func applySnapshot(_ snapshot: SystemSnapshot) async {
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
        await pushTrends(snapshot, at: Date())
        recordDiagnosticSnapshot(snapshot)
        recordSelfMonitoringSnapshot(snapshot)
    }

    private func recordDiagnosticSnapshot(_ snapshot: SystemSnapshot) {
        typealias Value = DiagnosticLogService.Value
        typealias Field = DiagnosticLogService.Field
        func field(_ value: Value) -> Field { .privateValue(value) }
        func optionalDouble(_ value: Double?) -> Field { field(value.map(Value.double) ?? .null) }
        func optionalInteger(_ value: Int?) -> Field {
            field(value.map { .integer(Int64($0)) } ?? .null)
        }

        let healthBreakdown = Value.object(snapshot.health.breakdown.mapValues(Value.double))
        var fields: [String: Field] = [:]
        fields["cpu.totalPercent"] = field(.double(snapshot.cpuUsage))
        fields["load.1m"] = field(.double(snapshot.loadAverage.load1))
        fields["gpu.percent"] = optionalDouble(snapshot.gpuUsage)
        fields["memory.pressure"] = field(.string(String(describing: snapshot.memoryPressure)))
        fields["memory.swapUsedBytes"] = field(.unsignedInteger(snapshot.swapUsed))
        fields["memory.swapActivityMBs"] = field(.double(snapshot.swapActivityMBs))
        fields["disk.readMBs"] = field(.double(snapshot.diskIO.readMBs))
        fields["disk.writeMBs"] = field(.double(snapshot.diskIO.writeMBs))
        fields["network.uploadBytesPerSecond"] = field(.double(snapshot.networkUpload))
        fields["network.downloadBytesPerSecond"] = field(.double(snapshot.networkDownload))
        fields["temperature.cpuCelsius"] = optionalDouble(snapshot.cpuTemperature)
        fields["temperature.thermalState"] = field(.string(snapshot.thermalState))
        fields["fan.rpm"] = optionalInteger(snapshot.fanSpeed)
        fields["battery.state"] = field(.string(String(describing: snapshot.battery.state)))
        fields["battery.percent"] = field(.double(snapshot.battery.percent))
        fields["battery.powerWatts"] = optionalDouble(snapshot.battery.powerWatts)
        fields["health.score"] = field(.integer(Int64(snapshot.health.score)))
        fields["health.breakdown"] = field(healthBreakdown)
        DiagnosticLogService.recordSample(category: "system", action: "collected", fields: fields)
    }

    private func recordSelfMonitoringSnapshot(_ snapshot: SystemSnapshot) {
        guard let sample = snapshot.selfMonitoring,
              let sessionID = snapshot.selfMonitoringSessionID else { return }
        typealias Value = DiagnosticLogService.Value
        typealias Field = DiagnosticLogService.Field
        func field(_ value: Value) -> Field { .privateValue(value) }
        func optionalDouble(_ value: Double?) -> Field { field(value.map(Value.double) ?? .null) }
        func optionalInteger(_ value: Int?) -> Field {
            field(value.map { .integer(Int64($0)) } ?? .null)
        }

        var fields: [String: Field] = [:]
        fields["session.id"] = .privateValue(sessionID)
        fields["app.cpu.percent"] = optionalDouble(sample.cpuPercent)
        fields["app.cpu.userSeconds"] = field(.double(sample.cpuUserSeconds))
        fields["app.cpu.systemSeconds"] = field(.double(sample.cpuSystemSeconds))
        fields["app.memory.physicalFootprintBytes"] = field(.unsignedInteger(sample.physicalFootprintBytes))
        fields["app.memory.peakPhysicalFootprintBytes"] = field(.unsignedInteger(sample.peakPhysicalFootprintBytes))
        fields["app.memory.residentBytes"] = field(.unsignedInteger(sample.residentBytes))
        fields["app.memory.wiredBytes"] = field(.unsignedInteger(sample.wiredBytes))
        fields["app.threadCount"] = optionalInteger(sample.threadCount)
        fields["app.wakeups.idle"] = field(.unsignedInteger(sample.idleWakeups))
        fields["app.wakeups.interrupt"] = field(.unsignedInteger(sample.interruptWakeups))
        fields["app.pageIns"] = field(.unsignedInteger(sample.pageIns))
        fields["app.disk.readBytes"] = field(.unsignedInteger(sample.diskBytesRead))
        fields["app.disk.writtenBytes"] = field(.unsignedInteger(sample.diskBytesWritten))
        fields["system.cpu.totalPercent"] = field(.double(snapshot.cpuUsage))
        fields["system.cpu.userPercent"] = field(.double(snapshot.cpuUserUsage))
        fields["system.cpu.systemPercent"] = field(.double(snapshot.cpuSystemUsage))
        fields["system.load.1m"] = field(.double(snapshot.loadAverage.load1))
        fields["system.load.5m"] = field(.double(snapshot.loadAverage.load5))
        fields["system.load.15m"] = field(.double(snapshot.loadAverage.load15))
        fields["system.gpu.percent"] = optionalDouble(snapshot.gpuUsage)
        fields["system.memory.usedBytes"] = field(.unsignedInteger(snapshot.memoryUsed))
        fields["system.memory.totalBytes"] = field(.unsignedInteger(snapshot.memoryTotal))
        fields["system.memory.usagePercent"] = field(.double(snapshot.memoryUsage))
        fields["system.memory.pressure"] = field(.string(String(describing: snapshot.memoryPressure)))
        fields["system.memory.swapUsedBytes"] = field(.unsignedInteger(snapshot.swapUsed))
        fields["system.memory.swapActivityMBs"] = field(.double(snapshot.swapActivityMBs))
        fields["system.disk.readMBs"] = field(.double(snapshot.diskIO.readMBs))
        fields["system.disk.writeMBs"] = field(.double(snapshot.diskIO.writeMBs))
        fields["system.network.uploadBytesPerSecond"] = field(.double(snapshot.networkUpload))
        fields["system.network.downloadBytesPerSecond"] = field(.double(snapshot.networkDownload))
        fields["system.temperature.cpuCelsius"] = optionalDouble(snapshot.cpuTemperature)
        fields["system.temperature.thermalState"] = field(.string(snapshot.thermalState))
        fields["system.fan.rpm"] = optionalInteger(snapshot.fanSpeed)
        fields["system.health.score"] = field(.integer(Int64(snapshot.health.score)))
        DiagnosticLogService.recordPerformanceSample(fields: fields)
    }

    private func restoreTrendHistory() {
        trendRestoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let samples = await trendStore.load()
            guard !Task.isCancelled else { return }
            applyRestoredTrends(samples)
            hasRestoredTrendHistory = true
            trendRestoreTask = nil
            requestUpdate()
        }
    }

    private func applyRestoredTrends(_ samples: [MetricTrendSample]) {
        trendSamples = samples
        trendAccumulator = nil
        lastTrendWriteAt = nil
        publishTrends()
    }

    /// 45 秒桶内持续聚合；桶结束时落盘，运行中的最后一点同步显示当前聚合结果。
    private func pushTrends(_ snapshot: SystemSnapshot, at date: Date) async {
        let sample = MetricTrendSample(
            timestamp: date,
            cpu: snapshot.cpuUsage,
            memory: snapshot.memoryUsage,
            gpu: snapshot.gpuUsage ?? 0,
            load: loadUsagePercent(snapshot),
            networkUp: snapshot.networkUpload,
            networkDown: snapshot.networkDownload
        )
        pruneTrendSamples(referenceDate: date)

        guard var accumulator = trendAccumulator else {
            startTrendBucket(with: sample)
            publishTrends()
            lastTrendWriteAt = date
            await trendStore.save(sample, referenceDate: date)
            return
        }

        if date.timeIntervalSince(accumulator.startedAt) >= MetricTrendStore.sampleInterval {
            let bucketEnd = accumulator.startedAt.addingTimeInterval(MetricTrendStore.sampleInterval)
            let completedSample = accumulator.aggregatedSample(endingAt: bucketEnd)
            let cutoff = date.addingTimeInterval(-MetricTrendStore.retention)
            let retainsCompletedSample = completedSample.timestamp >= cutoff
            if retainsCompletedSample {
                updateLiveTrendPoint(completedSample)
            }
            startTrendBucket(with: sample)
            publishTrends()
            if retainsCompletedSample {
                await trendStore.save(completedSample, referenceDate: date)
            }
            lastTrendWriteAt = date
            await trendStore.save(sample, referenceDate: date)
        } else {
            accumulator.add(sample)
            trendAccumulator = accumulator
            let aggregatedSample = accumulator.aggregatedSample()
            updateLiveTrendPoint(aggregatedSample)
            publishTrends()
            guard shouldWriteCurrentTrendBucket(at: date) else { return }
            lastTrendWriteAt = date
            await trendStore.save(aggregatedSample, referenceDate: date)
        }
    }

    private func shouldWriteCurrentTrendBucket(at date: Date) -> Bool {
        lastTrendWriteAt.map {
            date.timeIntervalSince($0) >= MetricTrendStore.provisionalWriteInterval
        } ?? true
    }

    private func startTrendBucket(with sample: MetricTrendSample) {
        trendAccumulator = MetricTrendAccumulator(sample: sample)
        trendSamples.append(sample)
        trimTrendSampleCount()
    }

    private func updateLiveTrendPoint(_ sample: MetricTrendSample) {
        if trendSamples.count < 2 {
            trendSamples.append(sample)
        } else {
            trendSamples[trendSamples.count - 1] = sample
        }
        trimTrendSampleCount()
    }

    private func pruneTrendSamples(referenceDate: Date) {
        let cutoff = referenceDate.addingTimeInterval(-MetricTrendStore.retention)
        trendSamples.removeAll { $0.timestamp < cutoff || $0.timestamp > referenceDate }
        trimTrendSampleCount()
    }

    private func trimTrendSampleCount() {
        let excess = trendSamples.count - MetricTrendStore.maximumSampleCount
        guard excess > 0 else { return }
        trendSamples.removeFirst(excess)
    }

    private func publishTrends() {
        trends = MetricTrends(
            cpu: trendSamples.map(\.cpu),
            memory: trendSamples.map(\.memory),
            gpu: trendSamples.map(\.gpu),
            load: trendSamples.map(\.load),
            networkUp: trendSamples.map(\.networkUp),
            networkDown: trendSamples.map(\.networkDown)
        )
    }

    /// 负载占用百分比：load1 ÷ 核心数，封顶 0–100。与 OverviewTabView 的口径一致。
    private func loadUsagePercent(_ snapshot: SystemSnapshot) -> Double {
        let coreCount = snapshot.coreTopology.totalCores > 0
            ? snapshot.coreTopology.totalCores
            : max(snapshot.coreUsages.count, 1)
        return min(100, max(0, snapshot.loadAverage.load1 / Double(coreCount) * 100))
    }
}
