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
        activeUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runUpdateLoop()
            self.activeUpdateTask = nil
        }
    }

    private func runUpdateLoop() async {
        while needsAnotherUpdate && !Task.isCancelled {
            needsAnotherUpdate = false
            isUpdating = true
            await updateRunningAppsInternal()
            isUpdating = false
        }
    }

    private func updateRunningAppsInternal() async {
        // Step 1: Collect all process memory rows; filtering/aggregation happens after attribution.
        let topProcesses = await processService.getTopMemoryProcesses(count: 0)
        
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
    }
    
    // MARK: - App Control
    
    /// Trigger system memory cleanup
    func triggerMemoryCleanup() async {
        await processService.triggerMemoryCleanup()
        await updateRunningApps()
    }
    
    /// Terminate an app group
    func terminateApp(_ app: AppGroup) -> Bool {
        processService.terminateApp(app)
    }
    
    /// Force terminate an app group
    func forceTerminateApp(_ app: AppGroup) -> Bool {
        processService.forceTerminateApp(app)
    }
    
    /// Async terminate with reliable two-stage strategy
    func terminateAppAsync(_ app: AppGroup) async -> Bool {
        let success = await processService.terminateAppAsync(app)
        if success {
            await updateRunningApps()
        }
        return success
    }
    
    /// Check if a process is still running
    func isProcessAlive(_ pid: pid_t) -> Bool {
        processService.isProcessAlive(pid)
    }

    /// Get child processes for an app group (excluding the main process)
    /// - Parameter app: The app group
    /// - Returns: Array of TopProcessInfo for child processes
    func childProcesses(for app: AppGroup) -> [TopProcessInfo] {
        return allTopProcesses.filter { app.allPids.contains($0.pid) && $0.pid != app.id }
            .sorted { $0.memoryBytes > $1.memoryBytes }
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
        var pidToBundleInfo: [pid_t: ProcessBundleInfo] = [:]
        let parentByPid = Dictionary(uniqueKeysWithValues: topProcesses.map { ($0.pid, $0.parentPid) })

        func bundleInfo(for pid: pid_t) -> ProcessBundleInfo {
            if let cached = pidToBundleInfo[pid] {
                return cached
            }
            let info = processService.getBundleInfo(for: pid)
            pidToBundleInfo[pid] = info
            return info
        }

        for process in topProcesses {
            let responsiblePid = responsibility_get_pid_responsible_for_pid(process.pid)
            let processBundleInfo = bundleInfo(for: process.pid)
            let responsibleBundleInfo = responsiblePid > 0 ? bundleInfo(for: responsiblePid) : nil

            if let resolution = resolveGroup(
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
            let resolvedBundleInfo = processService.getBundleInfo(for: pid)
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

    private func resolveGroup(
        for process: TopProcessInfo,
        responsiblePid: pid_t,
        processBundleInfo: ProcessBundleInfo,
        responsibleBundleInfo: ProcessBundleInfo?,
        monitoredByPid: [pid_t: String],
        monitoredByBundleId: [String: String],
        monitoredByBundlePath: [String: String],
        parentByPid: [pid_t: pid_t]
    ) -> ProcessGroupResolution? {
        if responsiblePid > 0, let key = monitoredByPid[responsiblePid] {
            return ProcessGroupResolution(groupKey: key, source: .responsibility)
        }
        if let bundleId = responsibleBundleInfo?.bundleId {
            if let key = monitoredByBundleId[bundleId] {
                return ProcessGroupResolution(groupKey: key, source: .responsibility)
            }
            if let key = inferredParentBundleGroupKey(
                for: bundleId,
                monitoredByBundleId: monitoredByBundleId
            ) {
                return ProcessGroupResolution(groupKey: key, source: .responsibility)
            }
        }
        if let bundleId = processBundleInfo.bundleId {
            if let key = monitoredByBundleId[bundleId] {
                return ProcessGroupResolution(groupKey: key, source: .bundle)
            }
            if let key = inferredParentBundleGroupKey(
                for: bundleId,
                monitoredByBundleId: monitoredByBundleId
            ) {
                return ProcessGroupResolution(groupKey: key, source: .bundle)
            }
        }
        if let bundlePath = responsibleBundleInfo?.bundlePath, let key = monitoredByBundlePath[bundlePath] {
            return ProcessGroupResolution(groupKey: key, source: .responsibility)
        }
        if let bundlePath = processBundleInfo.bundlePath, let key = monitoredByBundlePath[bundlePath] {
            return ProcessGroupResolution(groupKey: key, source: .bundle)
        }
        if let key = monitoredByPid[process.pid] {
            return ProcessGroupResolution(groupKey: key, source: .owningApp)
        }
        if let key = resolveGroupKeyFromParentChain(
            for: process,
            parentByPid: parentByPid,
            monitoredByPid: monitoredByPid
        ) {
            return ProcessGroupResolution(groupKey: key, source: .parentProcess)
        }
        return nil
    }

    private func resolveGroupKeyFromParentChain(
        for process: TopProcessInfo,
        parentByPid: [pid_t: pid_t],
        monitoredByPid: [pid_t: String]
    ) -> String? {
        var visited = Set<pid_t>()
        var parentPid = process.parentPid
        var depth = 0

        while parentPid > 1 && depth < 32 {
            if let key = monitoredByPid[parentPid] {
                return key
            }
            guard visited.insert(parentPid).inserted else { return nil }
            guard let nextParentPid = parentByPid[parentPid] else { return nil }
            parentPid = nextParentPid
            depth += 1
        }
        return nil
    }

    private func inferredParentBundleGroupKey(
        for bundleId: String,
        monitoredByBundleId: [String: String]
    ) -> String? {
        let components = bundleId
            .split(separator: ".")
            .map(String.init)
        guard components.count > 1 else { return nil }

        guard let lastComponent = components.last else { return nil }
        let lowerLast = lastComponent.lowercased()
        let helperMarkers = ["helper", "renderer", "gpu", "plugin", "utility", "extension", "xpc", "appex"]
        guard helperMarkers.contains(where: { lowerLast.contains($0) }) else { return nil }

        var parentComponents = components
        while parentComponents.count > 1 {
            parentComponents.removeLast()
            let parentBundleId = parentComponents.joined(separator: ".")
            if let key = monitoredByBundleId[parentBundleId] {
                return key
            }
        }
        return nil
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

private struct ProcessGroupResolution {
    let groupKey: String
    let source: ProcessAttributionSource
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
            return lhs.memoryBytes > rhs.memoryBytes
        }
        let totalMemory = sortedProcesses.reduce(0) { $0 + $1.memoryBytes }

        let allPids = pidSet.sorted()
        let terminablePids = terminablePidSet.sorted()
        return AppGroup(
            id: candidate.pid,
            name: candidate.name,
            icon: candidate.icon,
            totalMemoryBytes: totalMemory,
            processCount: allPids.count,
            allPids: allPids,
            terminablePids: terminablePids,
            isTerminable: true,
            bundleIdentifier: candidate.bundleIdentifier,
            bundlePath: candidate.bundlePath,
            execPath: candidate.execPath
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
            return lhs.memoryBytes > rhs.memoryBytes
        }
        let allPids = sortedProcesses.map(\.pid)
        let totalMemory = sortedProcesses.reduce(0) { $0 + $1.memoryBytes }

        return AppGroup(
            id: AppGroup.backgroundGroupId,
            name: "cleanup.backgroundProcesses".localized,
            icon: defaultIcon,
            totalMemoryBytes: totalMemory,
            processCount: allPids.count,
            allPids: allPids,
            terminablePids: [],
            isTerminable: false,
            bundleIdentifier: nil,
            bundlePath: nil,
            execPath: nil
        )
    }
}
