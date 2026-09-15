//
//  AppMemoryManager.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation
import AppKit
import Combine

// MARK: - App Memory Manager

/// Manages user application information and memory usage
@MainActor
final class AppMemoryManager: ObservableObject {

    /// 进行中的终止请求。AppDelegate 用它判断面板失焦时，焦点是否被「正在被关闭的目标应用」
    /// 合法截走（例如弹确认框并置前）。这属于正常情况，与无理由失焦区分开。
    struct ActiveTermination {
        let appName: String
        let bundleIdentifier: String?
        let pid: pid_t
        let forced: Bool
    }

    private(set) var activeTermination: ActiveTermination?

    @Published var runningApps: [AppGroup] = []
    @Published var totalMemoryUsed: UInt64 = 0
    @Published var totalMemory: UInt64 = 0
    @Published var appCount: Int = 0

    // Detailed memory info
    @Published var detailedMemory: MemoryInfo.DetailedInfo?
    @Published var memoryPressure: MemoryPressureLevel = .normal

    // 存储所有 top 进程信息，用于子进程查询
    private var allTopProcesses: [TopProcessInfo] = []

    private var timer: Timer?
    private var monitorInterval: TimeInterval = AppConfig.appMemoryRefreshInterval
    private var isMonitoring = false
    private var isUpdating = false
    private var needsAnotherUpdate = false
    private var activeUpdateTask: Task<Void, Never>?
    private var updateGeneration = 0

    static let shared = AppMemoryManager()

    /// ProcessService 实例
    private let processService: ProcessServiceProtocol

    /// 默认图标（缓存）
    private lazy var defaultAppIcon: NSImage = {
        NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }()

    private lazy var defaultGearIcon: NSImage = {
        NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) ?? NSImage()
    }()

    private init(processService: ProcessServiceProtocol? = nil) {
        self.processService = processService ?? ProcessService.shared
        totalMemory = ProcessInfo.processInfo.physicalMemory
    }

    func startMonitoring(interval: TimeInterval? = nil) {
        let refreshInterval = interval ?? AppConfig.appMemoryRefreshInterval
        let shouldRestartTimer = timer == nil || abs(refreshInterval - monitorInterval) > 0.001

        if !isMonitoring {
            isMonitoring = true
            monitorInterval = refreshInterval
            scheduleTimer(interval: refreshInterval)
            queueUpdate()
            return
        }

        if shouldRestartTimer {
            monitorInterval = refreshInterval
            scheduleTimer(interval: refreshInterval)
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        updateGeneration += 1
        activeUpdateTask?.cancel()
        activeUpdateTask = nil
        isUpdating = false
        needsAnotherUpdate = false
    }

    func updateRunningApps() async {
        queueUpdate()
        await activeUpdateTask?.value
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.queueUpdate()
            }
        }
    }

    private func queueUpdate() {
        needsAnotherUpdate = true

        guard activeUpdateTask == nil else { return }
        updateGeneration += 1
        let generation = updateGeneration
        activeUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runUpdateLoop()
            guard self.updateGeneration == generation else { return }
            self.activeUpdateTask = nil
        }
    }

    private func runUpdateLoop() async {
        while needsAnotherUpdate && !Task.isCancelled {
            needsAnotherUpdate = false
            isUpdating = true
            await updateRunningAppsInternal()
            guard !Task.isCancelled else { return }
            isUpdating = false
        }
    }

    private func updateRunningAppsInternal() async {
        // Step 1: Collect all process memory rows; filtering/aggregation happens after attribution.
        let topProcesses = await processService.getTopMemoryProcesses(count: 0)
        guard !Task.isCancelled else { return }

        // Step 2: Get running GUI apps for icons and bundle identifiers
        let workspace = NSWorkspace.shared
        let guiApps = workspace.runningApplications

        let appGroups = buildAppGroups(guiApps: guiApps, topProcesses: topProcesses)
        let detailedInfo = MemoryInfo.getDetailedMemoryInfo()

        objectWillChange.send()
        runningApps = appGroups
        allTopProcesses = topProcesses
        appCount = appGroups.count
        detailedMemory = detailedInfo
        totalMemoryUsed = detailedInfo.used
        memoryPressure = detailedInfo.pressureLevel
        DiagnosticLogService.recordSample(
            category: "processMemory",
            action: "collected",
            fields: [
                "appCount": .privateValue(.integer(Int64(appGroups.count))),
                "totalBytes": .privateValue(.unsignedInteger(detailedInfo.total)),
                "usedBytes": .privateValue(.unsignedInteger(detailedInfo.used)),
                "usagePercent": .privateValue(.double(detailedInfo.usagePercent)),
                "compressedBytes": .privateValue(.unsignedInteger(detailedInfo.compressed)),
                "pressure": .privateValue(.string(String(describing: detailedInfo.pressureLevel))),
                "swapUsedBytes": .privateValue(.unsignedInteger(detailedInfo.swapUsed))
            ]
        )
    }

    // MARK: - App Control

    /// Trigger system memory cleanup
    func triggerMemoryCleanup() async {
        DiagnosticLogService.record(category: "memoryCleanup", action: "requested")
        await processService.triggerMemoryCleanup()
        await updateRunningApps()
        DiagnosticLogService.record(category: "memoryCleanup", action: "completed")
    }

    /// Terminate an app group
    func terminateApp(_ app: AppGroup) -> Bool {
        activeTermination = Self.makeActiveTermination(app, forced: false)
        defer { activeTermination = nil }
        recordTerminationRequested(app, forced: false)
        let success = processService.terminateApp(app)
        recordTermination(app, forced: false, success: success)
        return success
    }

    /// Force terminate an app group
    func forceTerminateApp(_ app: AppGroup) -> Bool {
        activeTermination = Self.makeActiveTermination(app, forced: true)
        defer { activeTermination = nil }
        recordTerminationRequested(app, forced: true)
        let success = processService.forceTerminateApp(app)
        recordTermination(app, forced: true, success: success)
        return success
    }

    /// Async terminate with reliable two-stage strategy
    func terminateAppAsync(_ app: AppGroup) async -> Bool {
        let startedAt = Date()
        activeTermination = Self.makeActiveTermination(app, forced: false)
        defer { activeTermination = nil }
        recordTerminationRequested(app, forced: false)
        let success = await processService.terminateAppAsync(app)
        recordTermination(
            app,
            forced: false,
            success: success,
            durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
        )
        if success {
            await updateRunningApps()
        }
        return success
    }

    private static func makeActiveTermination(_ app: AppGroup, forced: Bool) -> ActiveTermination {
        ActiveTermination(
            appName: app.name,
            bundleIdentifier: app.bundleIdentifier,
            pid: app.id,
            forced: forced
        )
    }

    private func recordTerminationRequested(_ app: AppGroup, forced: Bool) {
        DiagnosticLogService.record(
            category: "process",
            action: "terminationRequested",
            fields: [
                "name": app.name,
                "pid": String(app.id),
                "bundleIdentifier": app.bundleIdentifier ?? "none",
                "processCount": String(app.processCount),
                "forced": String(forced),
                "frontmostBundleIdentifier": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none",
                "lightStatsActive": String(NSApp.isActive)
            ]
        )
    }

    private func recordTermination(
        _ app: AppGroup,
        forced: Bool,
        success: Bool,
        durationMilliseconds: Int? = nil
    ) {
        var fields = [
            "name": app.name,
            "pid": String(app.id),
            "bundleIdentifier": app.bundleIdentifier ?? "none",
            "forced": String(forced),
            "success": String(success)
        ]
        if let durationMilliseconds {
            fields["durationMilliseconds"] = String(durationMilliseconds)
        }
        DiagnosticLogService.record(
            level: success ? .info : .error,
            category: "process",
            action: "terminationCompleted",
            fields: fields
        )
    }

    /// Check if a process is still running
    func isProcessAlive(_ pid: pid_t) -> Bool {
        processService.isProcessAlive(pid)
    }

    /// Get child processes for an app group (excluding the main process)
    /// - Parameter app: The app group
    /// - Returns: Array of TopProcessInfo for child processes
    func childProcesses(for app: AppGroup) -> [TopProcessInfo] {
        let pidSet = Set(app.allPids)
        return allTopProcesses.filter { pidSet.contains($0.pid) && $0.pid != app.id }
            .sorted { ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0) }
    }

    private func buildAppGroups(guiApps: [NSRunningApplication], topProcesses: [TopProcessInfo]) -> [AppGroup] {
        let monitoredApps = buildMonitoredAppCandidates(from: guiApps)
        var monitoredByKey: [String: MonitoredAppCandidate] = [:]
        var monitoredByPid: [pid_t: String] = [:]
        var monitoredByBundleId: [String: String] = [:]
        var monitoredByBundlePath: [String: String] = [:]

        for candidate in monitoredApps {
            let key = candidate.groupKey
            if let existing = monitoredByKey[key] {
                monitoredByKey[key] = preferredMonitoredCandidate(existing, candidate)
            } else {
                monitoredByKey[key] = candidate
            }
            monitoredByPid[candidate.pid] = key
            if let bundleId = candidate.bundleInfo.bundleId, monitoredByBundleId[bundleId] == nil {
                monitoredByBundleId[bundleId] = key
            }
            if let bundlePath = candidate.bundleInfo.bundlePath, monitoredByBundlePath[bundlePath] == nil {
                monitoredByBundlePath[bundlePath] = key
            }
        }

        var accumulators: [String: AppGroupAccumulator] = [:]
        var backgroundAccumulator = BackgroundProcessAccumulator(defaultIcon: defaultGearIcon)
        let pidToBundleInfo = Dictionary(topProcesses.map { ($0.pid, $0.bundleInfo) }, uniquingKeysWith: { first, _ in first })
        let parentByPid = Dictionary(topProcesses.map { ($0.pid, $0.parentPid) }, uniquingKeysWith: { first, _ in first })

        for process in topProcesses {
            let responsiblePid = process.responsiblePid
            let processBundleInfo = process.bundleInfo
            let responsibleBundleInfo = pidToBundleInfo[responsiblePid]

            if let resolution = ProcessAttributionPolicy.resolveGroup(
                for: process,
                responsiblePid: responsiblePid,
                processBundleInfo: processBundleInfo,
                responsibleBundleInfo: responsibleBundleInfo,
                monitoredByPid: monitoredByPid,
                monitoredByBundleId: monitoredByBundleId,
                monitoredByBundlePath: monitoredByBundlePath,
                parentByPid: parentByPid
            ) {
                let groupKey = resolution.groupKey
                if accumulators[groupKey] == nil, let candidate = monitoredByKey[groupKey] {
                    accumulators[groupKey] = AppGroupAccumulator(candidate: candidate)
                }
                accumulators[groupKey]?.add(process, attributionSource: resolution.source)
            } else if shouldShowProcess(processBundleInfo, processName: process.command) {
                backgroundAccumulator.add(process)
            }
        }

        var groups = accumulators.values
            .compactMap { $0.makeAppGroup() }
            .sorted {
                if $0.totalMemoryBytes == $1.totalMemoryBytes {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.totalMemoryBytes > $1.totalMemoryBytes
            }
        if let backgroundGroup = backgroundAccumulator.makeAppGroup() {
            groups.append(backgroundGroup)
        }
        return groups
    }

    private func buildMonitoredAppCandidates(from guiApps: [NSRunningApplication]) -> [MonitoredAppCandidate] {
        guiApps.compactMap { app in
            guard app.activationPolicy == .regular || app.activationPolicy == .accessory else { return nil }
            let pid = app.processIdentifier
            guard pid > 0 else { return nil }

            let guiBundlePath = app.bundleURL?.path
            let guiExecPath = app.executableURL?.path
            let guiBundleId = app.bundleIdentifier
            let guiBundleInfo = ProcessBundleInfo(execPath: guiExecPath, bundlePath: guiBundlePath, bundleId: guiBundleId)
            guard shouldShowProcess(guiBundleInfo, processName: app.localizedName) else { return nil }

            // Canonicalize helper/accessory processes to the root app bundle whenever possible.
            let resolvedBundleInfo = guiExecPath.map(ProcessBundleResolver.resolve) ?? guiBundleInfo
            let canonicalBundleInfo = ProcessBundleInfo(
                execPath: resolvedBundleInfo.execPath ?? guiExecPath,
                bundlePath: resolvedBundleInfo.bundlePath ?? guiBundlePath,
                bundleId: resolvedBundleInfo.bundleId ?? guiBundleId
            )

            return MonitoredAppCandidate(
                pid: pid,
                name: app.localizedName ?? processService.getProcessName(for: pid) ?? "Unknown",
                icon: app.icon ?? defaultAppIcon,
                bundleIdentifier: canonicalBundleInfo.bundleId,
                bundlePath: canonicalBundleInfo.bundlePath,
                execPath: canonicalBundleInfo.execPath,
                bundleInfo: canonicalBundleInfo,
                activationPolicy: app.activationPolicy
            )
        }
    }

    private func preferredMonitoredCandidate(
        _ lhs: MonitoredAppCandidate,
        _ rhs: MonitoredAppCandidate
    ) -> MonitoredAppCandidate {
        let lhsScore = monitoredCandidateScore(lhs)
        let rhsScore = monitoredCandidateScore(rhs)
        if lhsScore == rhsScore {
            return lhs.pid <= rhs.pid ? lhs : rhs
        }
        return lhsScore > rhsScore ? lhs : rhs
    }

    private func monitoredCandidateScore(_ candidate: MonitoredAppCandidate) -> Int {
        var score = 0
        switch candidate.activationPolicy {
        case .regular:
            score += 200
        case .accessory:
            score += 100
        default:
            break
        }
        if !isLikelyHelperCandidateName(candidate.name) {
            score += 40
        }
        if candidate.bundleInfo.bundleId != nil {
            score += 20
        }
        if candidate.bundleInfo.bundlePath != nil {
            score += 10
        }
        return score
    }

    private func isLikelyHelperCandidateName(_ name: String) -> Bool {
        let lowerName = name.lowercased()
        let helperKeywords = ["helper", "renderer", "gpu", "plugin", "utility", "extension"]
        return helperKeywords.contains { lowerName.contains($0) }
    }

}

private struct MonitoredAppCandidate {
    let pid: pid_t
    let name: String
    let icon: NSImage
    let bundleIdentifier: String?
    let bundlePath: String?
    let execPath: String?
    let bundleInfo: ProcessBundleInfo
    let activationPolicy: NSApplication.ActivationPolicy

    var groupKey: String {
        if let bundleId = bundleInfo.bundleId, !bundleId.isEmpty {
            return "bundle:\(bundleId)"
        }
        if let bundlePath = bundleInfo.bundlePath, !bundlePath.isEmpty {
            return "path:\(bundlePath)"
        }
        return "app:\(pid)"
    }
}

private struct AppGroupAccumulator {
    private let candidate: MonitoredAppCandidate
    private(set) var assignedProcesses: [TopProcessInfo] = []
    private var pidSet: Set<pid_t>
    private var terminablePidSet: Set<pid_t>

    init(candidate: MonitoredAppCandidate) {
        self.candidate = candidate
        self.pidSet = [candidate.pid]
        self.terminablePidSet = [candidate.pid]
    }

    mutating func add(_ process: TopProcessInfo, attributionSource: ProcessAttributionSource) {
        assignedProcesses.append(process)
        pidSet.insert(process.pid)
        if attributionSource.canTerminateWithApp {
            terminablePidSet.insert(process.pid)
        }
    }

    func makeAppGroup() -> AppGroup? {
        let sortedProcesses = assignedProcesses.sorted { lhs, rhs in
            if lhs.memoryBytes == rhs.memoryBytes {
                return lhs.pid < rhs.pid
            }
            return (lhs.memoryBytes ?? 0) > (rhs.memoryBytes ?? 0)
        }
        let memory = ProcessMemorySummary(sortedProcesses.map(\.memoryBytes))

        let allPids = pidSet.sorted()
        let terminablePids = terminablePidSet.sorted()
        return AppGroup(
            id: candidate.pid,
            name: candidate.name,
            icon: candidate.icon,
            totalMemoryBytes: memory.knownBytes,
            processCount: allPids.count,
            allPids: allPids,
            terminablePids: terminablePids,
            isTerminable: sortedProcesses.contains { $0.identity.pid == candidate.pid },
            bundleIdentifier: candidate.bundleIdentifier,
            bundlePath: candidate.bundlePath,
            execPath: candidate.execPath,
            processIdentities: Dictionary(sortedProcesses.map { ($0.pid, $0.identity) }, uniquingKeysWith: { first, _ in first }),
            unavailableMemoryCount: memory.unavailableCount
                + (sortedProcesses.contains { $0.pid == candidate.pid } ? 0 : 1)
        )
    }
}

private struct BackgroundProcessAccumulator {
    private let defaultIcon: NSImage
    private var processes: [TopProcessInfo] = []

    init(defaultIcon: NSImage) {
        self.defaultIcon = defaultIcon
    }

    mutating func add(_ process: TopProcessInfo) {
        processes.append(process)
    }

    func makeAppGroup() -> AppGroup? {
        guard !processes.isEmpty else { return nil }
        let sortedProcesses = processes.sorted { lhs, rhs in
            if lhs.memoryBytes == rhs.memoryBytes {
                return lhs.pid < rhs.pid
            }
            return (lhs.memoryBytes ?? 0) > (rhs.memoryBytes ?? 0)
        }
        let allPids = sortedProcesses.map(\.pid)
        let memory = ProcessMemorySummary(sortedProcesses.map(\.memoryBytes))

        return AppGroup(
            id: AppGroup.backgroundGroupId,
            name: "cleanup.backgroundProcesses".localized,
            icon: defaultIcon,
            totalMemoryBytes: memory.knownBytes,
            processCount: allPids.count,
            allPids: allPids,
            terminablePids: [],
            isTerminable: false,
            bundleIdentifier: nil,
            bundlePath: nil,
            execPath: nil,
            unavailableMemoryCount: memory.unavailableCount
        )
    }
}
