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
        var pidToBundleInfo: [pid_t: ProcessBundleInfo] = [:]

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

            if let groupKey = resolveGroupKey(
                for: process,
                responsiblePid: responsiblePid,
                processBundleInfo: processBundleInfo,
                responsibleBundleInfo: responsibleBundleInfo,
                monitoredByPid: monitoredByPid,
                monitoredByBundleId: monitoredByBundleId,
                monitoredByBundlePath: monitoredByBundlePath
            ) {
                if accumulators[groupKey] == nil, let candidate = monitoredByKey[groupKey] {
                    accumulators[groupKey] = AppGroupAccumulator(candidate: candidate)
                }
                accumulators[groupKey]?.add(process)
                continue
            }

            let standalone = StandaloneGroupDescriptor(
                process: process,
                bundleInfo: processBundleInfo,
                processService: processService
            )
            guard shouldShowProcess(standalone.bundleInfo, processName: standalone.process.command) else {
                continue
            }

            let key = standalone.groupKey
            if accumulators[key] == nil {
                accumulators[key] = AppGroupAccumulator(standalone: standalone, defaultIcon: defaultGearIcon)
            }
            accumulators[key]?.add(process)
        }

        return accumulators.values
            .compactMap { $0.makeAppGroup(defaultAppIcon: defaultAppIcon, processService: processService) }
            .sorted {
                if $0.totalMemoryBytes == $1.totalMemoryBytes {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.totalMemoryBytes > $1.totalMemoryBytes
            }
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

    private func resolveGroupKey(
        for process: TopProcessInfo,
        responsiblePid: pid_t,
        processBundleInfo: ProcessBundleInfo,
        responsibleBundleInfo: ProcessBundleInfo?,
        monitoredByPid: [pid_t: String],
        monitoredByBundleId: [String: String],
        monitoredByBundlePath: [String: String]
    ) -> String? {
        if responsiblePid > 0, let key = monitoredByPid[responsiblePid] {
            return key
        }
        if let bundleId = responsibleBundleInfo?.bundleId {
            if let key = monitoredByBundleId[bundleId] {
                return key
            }
            if let key = inferredParentBundleGroupKey(
                for: bundleId,
                monitoredByBundleId: monitoredByBundleId
            ) {
                return key
            }
        }
        if let bundleId = processBundleInfo.bundleId {
            if let key = monitoredByBundleId[bundleId] {
                return key
            }
            if let key = inferredParentBundleGroupKey(
                for: bundleId,
                monitoredByBundleId: monitoredByBundleId
            ) {
                return key
            }
        }
        if let bundlePath = responsibleBundleInfo?.bundlePath, let key = monitoredByBundlePath[bundlePath] {
            return key
        }
        if let bundlePath = processBundleInfo.bundlePath, let key = monitoredByBundlePath[bundlePath] {
            return key
        }
        if let key = monitoredByPid[process.pid] {
            return key
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

private struct StandaloneGroupDescriptor {
    let groupKey: String
    let seedPid: pid_t
    let name: String
    let bundleInfo: ProcessBundleInfo
    let process: TopProcessInfo

    init(process: TopProcessInfo, bundleInfo: ProcessBundleInfo, processService: ProcessServiceProtocol) {
        self.process = process
        self.bundleInfo = bundleInfo
        self.seedPid = process.pid

        if let bundleId = bundleInfo.bundleId, !bundleId.isEmpty {
            self.groupKey = "bundle:\(bundleId)"
        } else if let bundlePath = bundleInfo.bundlePath, !bundlePath.isEmpty {
            self.groupKey = "path:\(bundlePath)"
        } else {
            self.groupKey = "pid:\(process.pid)"
        }

        if let bundlePath = bundleInfo.bundlePath, let bundle = Bundle(path: bundlePath) {
            self.name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? processService.getProcessName(for: process.pid)
                ?? process.command
        } else {
            self.name = processService.getProcessName(for: process.pid) ?? process.command
        }
    }
}

private struct AppGroupAccumulator {
    private let candidate: MonitoredAppCandidate?
    private let standalone: StandaloneGroupDescriptor?
    private let fallbackIcon: NSImage
    private(set) var assignedProcesses: [TopProcessInfo] = []
    private var pidSet: Set<pid_t>

    init(candidate: MonitoredAppCandidate) {
        self.candidate = candidate
        self.standalone = nil
        self.fallbackIcon = candidate.icon
        self.pidSet = [candidate.pid]
    }

    init(standalone: StandaloneGroupDescriptor, defaultIcon: NSImage) {
        self.candidate = nil
        self.standalone = standalone
        self.fallbackIcon = defaultIcon
        self.pidSet = [standalone.seedPid]
    }

    mutating func add(_ process: TopProcessInfo) {
        assignedProcesses.append(process)
        pidSet.insert(process.pid)
    }

    func makeAppGroup(defaultAppIcon: NSImage, processService: ProcessServiceProtocol) -> AppGroup? {
        let sortedProcesses = assignedProcesses.sorted { lhs, rhs in
            if lhs.memoryBytes == rhs.memoryBytes {
                return lhs.pid < rhs.pid
            }
            return lhs.memoryBytes > rhs.memoryBytes
        }
        let totalMemory = sortedProcesses.reduce(0) { $0 + $1.memoryBytes }

        if let candidate {
            let allPids = Array(pidSet)
            return AppGroup(
                id: candidate.pid,
                name: candidate.name,
                icon: candidate.icon,
                totalMemoryBytes: totalMemory,
                processCount: allPids.count,
                allPids: allPids,
                bundleIdentifier: candidate.bundleIdentifier,
                bundlePath: candidate.bundlePath,
                execPath: candidate.execPath
            )
        }

        guard let standalone else { return nil }
        let primaryPid = sortedProcesses.first?.pid ?? standalone.seedPid
        let allPids = Array(pidSet)
        return AppGroup(
            id: primaryPid,
            name: standalone.name,
            icon: fallbackIcon,
            totalMemoryBytes: totalMemory,
            processCount: allPids.count,
            allPids: allPids,
            bundleIdentifier: standalone.bundleInfo.bundleId,
            bundlePath: standalone.bundleInfo.bundlePath,
            execPath: standalone.bundleInfo.execPath
        )
    }
}
