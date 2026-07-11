//
//  UsageWarmupService.swift
//  Light Stats
//
//  Created on 2026/06/28.
//
//  Sends a throwaway headless CLI message to keep the rolling usage window warm
//  (the in-app version of a periodic `/loop` ping). Unlike the read-only `/usage`
//  probes elsewhere, this sends a real prompt. Fire-and-wait with a hard timeout
//  and SIGTERM→SIGKILL escalation; output is discarded except a capped stderr
//  snippet on failure. Runs in a throwaway empty cwd so no project CLAUDE.md /
//  AGENTS.md context is loaded.
//

import Foundation
import os

/// Sends warmup messages for providers that have a rolling window (Claude, Codex).
/// Returns `true` iff the CLI exited 0 — i.e. it is installed and logged in.
nonisolated enum UsageWarmupService {

    private static let log = AppLogger(
        subsystem: "com.lightstats.app",
        category: "UsageWarmup",
        mirrorsToJournal: false
    )
    private static let maxStderrLogBytes = 2_048

    /// 窗口 anchor 只需要发出一条真实消息；内容越短，warmup 的 token 成本越低。
    static let prompt = "ok"

    static func send(provider: AIProvider, timeout: TimeInterval = 30) async -> Bool {
        guard provider != .gemini else { return false }   // 每日 quota，无滚动窗口可 anchor
        guard let binary = binary(for: provider) else {
            log.error("warmup: \(provider.rawValue) binary not found")
            DiagnosticLogService.record(
                level: .error,
                category: "usageWarmup.command",
                action: "binaryNotFound",
                fields: ["provider": provider.rawValue]
            )
            return false
        }
        let ok = await run(binary: binary, arguments: arguments(for: provider), timeout: timeout)
        log.info("warmup \(provider.rawValue) ok=\(ok)")
        DiagnosticLogService.record(
            level: ok ? .info : .error,
            category: "usageWarmup.command",
            action: "completed",
            fields: ["provider": provider.rawValue, "success": String(ok)]
        )
        return ok
    }

    // MARK: - Command shape

    private static func binary(for provider: AIProvider) -> String? {
        switch provider {
        case .claude: return CLIBinaryResolver.resolveClaudeBinary()
        case .codex: return CLIBinaryResolver.resolveCodexBinary()
        case .gemini: return nil
        }
    }

    /// 尽量压小上下文：Claude 用 `-p` print 模式并禁用工具；Codex 用 `exec` 只读沙箱、
    /// 跳过 git 检查、忽略用户规则/配置并不落 session 文件（配合空 cwd，避免加载仓库上下文）。
    private static func arguments(for provider: AIProvider) -> [String] {
        switch provider {
        case .claude: return ["-p", prompt, "--allowed-tools", ""]
        case .codex:
            return [
                "exec", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check", "--ephemeral",
                "-s", "read-only", prompt
            ]
        case .gemini: return []
        }
    }

    // MARK: - Process runner

    /// Runs the process in a throwaway empty cwd, waits for exit with a hard timeout,
    /// and force-kills on timeout or task cancellation. Never blocks the caller's actor.
    private static func run(binary: String, arguments: [String], timeout: TimeInterval) async -> Bool {
        let workDir = makeScratchDir()
        defer { if let workDir { try? FileManager.default.removeItem(at: workDir) } }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.environment = CLIBinaryResolver.enrichedEnvironment()
        if let workDir { process.currentDirectoryURL = workDir }
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let stderr = LimitedPipeCapture(limit: maxStderrLogBytes)
        process.standardError = stderr.pipe

        let box = ProcessBox(process)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                process.terminationHandler = { proc in
                    box.cancelTimers()
                    let ok = proc.terminationStatus == 0
                    if !ok {
                        let stderrText = stderr.finish()
                        log.error(
                            "warmup failed status=\(proc.terminationStatus) stderr=\(stderrText)"
                        )
                        DiagnosticLogService.record(
                            level: .error,
                            category: "usageWarmup.command",
                            action: "processFailed",
                            fields: ["exitStatus": String(proc.terminationStatus), "stderr": stderrText]
                        )
                    } else {
                        stderr.finish()
                    }
                    cont.resume(returning: ok)
                }
                do {
                    try process.run()
                } catch {
                    log.error("warmup: launch failed: \(error.localizedDescription)")
                    DiagnosticLogService.record(
                        level: .error,
                        category: "usageWarmup.command",
                        action: "launchFailed",
                        fields: ["error": error.localizedDescription]
                    )
                    cont.resume(returning: false)
                    return
                }
                box.armTimeout(timeout)
            }
        } onCancel: {
            box.kill()
        }
    }

    private static func makeScratchDir() -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lightstats-warmup-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }
}

/// Captures a bounded stderr sample so background warmup failures are diagnosable
/// without risking an unbounded pipe buffer.
private final class LimitedPipeCapture: @unchecked Sendable {
    let pipe = Pipe()

    private let limit: Int
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false
    private var finished = false

    init(limit: Int) {
        self.limit = limit
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.append(chunk)
        }
    }

    func finish() -> String {
        lock.lock()
        if finished {
            let value = formattedText()
            lock.unlock()
            return value
        }
        finished = true
        lock.unlock()

        pipe.fileHandleForReading.readabilityHandler = nil
        append(pipe.fileHandleForReading.readDataToEndOfFile())

        lock.lock()
        let value = formattedText()
        lock.unlock()
        return value
    }

    private func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let remaining = limit - data.count
        if remaining > 0 {
            data.append(chunk.prefix(remaining))
        }
        if chunk.count > max(remaining, 0) {
            truncated = true
        }
    }

    private func formattedText() -> String {
        let text = (String(data: data, encoding: .utf8) ?? "<non-utf8 stderr>")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = truncated ? " [truncated]" : ""
        return text.isEmpty ? "<empty>\(suffix)" : "\(text)\(suffix)"
    }
}

/// Owns the timeout/kill machinery for a single warmup process. `@unchecked
/// Sendable`: all mutable access is serialised on `queue`; `Process.terminate()`
/// and `kill(2)` are safe to call from any thread.
private final class ProcessBox: @unchecked Sendable {
    private let process: Process
    private let queue = DispatchQueue(label: "com.lightstats.warmup.timeout")
    private var timeoutItem: DispatchWorkItem?
    private var killItem: DispatchWorkItem?

    init(_ process: Process) { self.process = process }

    /// 软超时：到点 SIGTERM；若 3s 内仍不退，升级 SIGKILL。
    func armTimeout(_ timeout: TimeInterval) {
        let soft = DispatchWorkItem { [weak self] in self?.terminate() }
        queue.async { [weak self] in self?.timeoutItem = soft }
        queue.asyncAfter(deadline: .now() + timeout, execute: soft)
    }

    func cancelTimers() {
        queue.async { [weak self] in
            self?.timeoutItem?.cancel()
            self?.killItem?.cancel()
        }
    }

    func kill() {
        queue.async { [weak self] in
            guard let self, self.process.isRunning else { return }
            self.process.terminate()
            Darwin.kill(self.process.processIdentifier, SIGKILL)
        }
    }

    private func terminate() {
        guard process.isRunning else { return }
        process.terminate()   // SIGTERM
        let hard = DispatchWorkItem { [weak self] in
            guard let self, self.process.isRunning else { return }
            Darwin.kill(self.process.processIdentifier, SIGKILL)
        }
        queue.async { [weak self] in self?.killItem = hard }
        queue.asyncAfter(deadline: .now() + 3, execute: hard)
    }
}
