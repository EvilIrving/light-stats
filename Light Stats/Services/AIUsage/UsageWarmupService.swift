//
//  UsageWarmupService.swift
//  Light Stats
//
//  Created on 2026/06/28.
//
//  Sends a throwaway headless CLI message ("warmup") to anchor a fresh rolling
//  usage window. Unlike the read-only `/usage` probes elsewhere, this sends a
//  real prompt (the only thing that starts a window). Fire-and-wait with a hard
//  timeout and SIGTERM→SIGKILL escalation; output is discarded. Runs in a throwaway
//  empty cwd so no project CLAUDE.md / AGENTS.md context is loaded.
//

import Foundation
import os

/// Sends warmup messages for providers that have a rolling window (Claude, Codex).
/// Returns `true` iff the CLI exited 0 — i.e. it is installed and logged in.
nonisolated enum UsageWarmupService {

    private static let log = Logger(subsystem: "com.lightstats.app", category: "UsageWarmup")

    /// 一句无害的自然语言；anchor 窗口只需要"发出一条真实消息"，内容无所谓。
    static let prompt = "今天天气怎么样？"

    static func send(provider: AIProvider, timeout: TimeInterval = 30) async -> Bool {
        guard provider != .gemini else { return false }   // 每日 quota，无滚动窗口可 anchor
        guard let binary = binary(for: provider) else {
            log.error("warmup: \(provider.rawValue, privacy: .public) binary not found")
            return false
        }
        let ok = await run(binary: binary, arguments: arguments(for: provider), timeout: timeout)
        log.info("warmup \(provider.rawValue, privacy: .public) ok=\(ok, privacy: .public)")
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
    /// 跳过 git 检查（配合空 cwd，避免加载仓库上下文）。
    private static func arguments(for provider: AIProvider) -> [String] {
        switch provider {
        case .claude: return ["-p", prompt, "--allowed-tools", ""]
        case .codex: return ["exec", "--skip-git-repo-check", "-s", "read-only", prompt]
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
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let box = ProcessBox(process)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                process.terminationHandler = { proc in
                    box.cancelTimers()
                    cont.resume(returning: proc.terminationStatus == 0)
                }
                do {
                    try process.run()
                } catch {
                    log.error("warmup: launch failed: \(error.localizedDescription, privacy: .public)")
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
