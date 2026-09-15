//
//  ProcessService.swift
//  Light Stats
//
//  进程相关服务：原生进程采样、进程信息查询、进程控制
//

import Foundation
import AppKit

// MARK: - Responsibility Framework

/// Import the responsibility framework for process grouping
/// responsibility_get_pid_responsible_for_pid returns the PID of the "responsible" process
@_silgen_name("responsibility_get_pid_responsible_for_pid")
nonisolated func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

// MARK: - Process Service

/// 进程服务：提供进程信息查询、原生进程采样、进程控制功能
protocol ProcessServiceProtocol {
    func getBundleInfo(for pid: pid_t) -> ProcessBundleInfo
    func getProcessName(for pid: pid_t) -> String?
    func getTopMemoryProcesses(count: Int) async -> [TopProcessInfo]
    func triggerMemoryCleanup() async
    func terminateApp(_ app: AppGroup) -> Bool
    func forceTerminateApp(_ app: AppGroup) -> Bool
    func terminateAppAsync(_ app: AppGroup) async -> Bool
    func isProcessAlive(_ pid: pid_t) -> Bool
}

final class ProcessService: ProcessServiceProtocol {

    static let shared = ProcessService()

    private let memoryCleanupLock = NSLock()
    private var isMemoryCleanupRunning = false

    private init() {}

    // MARK: - Bundle Info Extraction

    /// 从进程 PID 获取 Bundle 信息
    /// - Parameter pid: 进程 PID
    /// - Returns: ProcessBundleInfo 包含可执行文件路径、Bundle 路径和 Bundle ID
    func getBundleInfo(for pid: pid_t) -> ProcessBundleInfo {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else {
            return ProcessBundleInfo(execPath: nil, bundlePath: nil, bundleId: nil)
        }
        return ProcessBundleResolver.resolve(String(cString: pathBuffer))
    }

    /// Get process name for a given PID
    func getProcessName(for pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))

        if pathLength > 0 {
            let path = String(cString: pathBuffer)
            return (path as NSString).lastPathComponent
        }

        // Fallback: try to get name from kinfo_proc
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        if sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 && size > 0 {
            let name = withUnsafePointer(to: &info.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }
            if !name.isEmpty {
                return name
            }
        }

        return nil
    }

    // MARK: - Native Sampling

    func getTopMemoryProcesses(count: Int) async -> [TopProcessInfo] {
        let rows = await ProcessSampler.shared.sample().sorted {
            if $0.memoryBytes == $1.memoryBytes { return $0.pid < $1.pid }
            return ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0)
        }
        return count > 0 ? Array(rows.prefix(count)) : rows
    }

    // MARK: - Process Control

    func isProcessAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private func killProcessGracefully(_ identity: ProcessIdentity) async -> Bool {
        guard ProcessSignalGuard.send(SIGTERM, to: identity) else { return false }
        do {
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            return false
        }
        guard isProcessAlive(identity.pid) else { return true }
        return ProcessSignalGuard.send(SIGKILL, to: identity)
    }

    func terminateAppAsync(_ app: AppGroup) async -> Bool {
        guard let identity = verifiedMainIdentity(app) else { return false }
        if let mainApp = NSRunningApplication(processIdentifier: app.id),
           ProcessIdentityReader.read(app.id) == identity, mainApp.terminate() {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return false
            }
            if !isProcessAlive(app.id) {
                await terminateSurvivingTerminableChildren(app)
                return true
            }
        }
        let success = await killProcessGracefully(identity)
        if success { await terminateSurvivingTerminableChildren(app) }
        return success
    }

    private func verifiedMainIdentity(_ app: AppGroup) -> ProcessIdentity? {
        guard app.isTerminable, let identity = app.processIdentities[app.id],
              ProcessIdentityReader.read(app.id) == identity else { return nil }
        return identity
    }

    private func terminateSurvivingTerminableChildren(_ app: AppGroup) async {
        for pid in app.terminablePids where pid != app.id {
            guard !Task.isCancelled else { return }
            guard let identity = app.processIdentities[pid], isProcessAlive(pid) else { continue }
            _ = await killProcessGracefully(identity)
        }
    }

    /// Trigger system memory cleanup
    /// Uses memory pressure simulation to encourage system to release purgeable memory
    func triggerMemoryCleanup() async {
        guard beginMemoryCleanup() else { return }
        defer { endMemoryCleanup() }

        await Task.detached(priority: .utility) {
            // Method 1: Allocate and release memory to trigger system cleanup
            // This is a safer approach than running 'purge' command which requires sudo
            let chunkSize = 100 * 1024 * 1024  // 100 MB chunks
            var chunks: [UnsafeMutableRawPointer] = []

            // Allocate memory to create pressure
            for _ in 0..<5 {
                if let chunk = malloc(chunkSize) {
                    memset(chunk, 0, chunkSize)  // Touch the memory
                    chunks.append(chunk)
                }
            }

            // Small delay
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second

            // Free the allocated memory
            for chunk in chunks {
                free(chunk)
            }
        }.value
    }

    private func beginMemoryCleanup() -> Bool {
        memoryCleanupLock.lock()
        defer { memoryCleanupLock.unlock() }
        guard !isMemoryCleanupRunning else { return false }
        isMemoryCleanupRunning = true
        return true
    }

    private func endMemoryCleanup() {
        memoryCleanupLock.lock()
        isMemoryCleanupRunning = false
        memoryCleanupLock.unlock()
    }

    func terminateApp(_ app: AppGroup) -> Bool {
        guard let identity = verifiedMainIdentity(app),
              let mainApp = NSRunningApplication(processIdentifier: app.id),
              ProcessIdentityReader.read(app.id) == identity else { return false }
        return mainApp.terminate()
    }

    func forceTerminateApp(_ app: AppGroup) -> Bool {
        guard let identity = verifiedMainIdentity(app),
              ProcessSignalGuard.send(SIGKILL, to: identity) else { return false }
        var allSucceeded = true
        for pid in app.terminablePids where pid != app.id {
            guard isProcessAlive(pid) else { continue }
            guard let child = app.processIdentities[pid], ProcessSignalGuard.send(SIGKILL, to: child) else {
                allSucceeded = false
                continue
            }
        }
        return allSucceeded
    }
}

import Darwin
