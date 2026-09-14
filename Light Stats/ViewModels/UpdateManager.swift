//
//  UpdateManager.swift
//  Light Stats
//
//  更新协调层（@MainActor）。`check(userInitiated:)` 是统一、可复用的入口:
//  先静默检查 → 仅当发现新版本时才弹出更新窗口;无新版/出错时(用户主动触发)
//  主动检查失败时显示可恢复的错误窗口；检查中状态由 isChecking 暴露给入口。
//

import AppKit
import SwiftUI
import Combine
import os

@MainActor
final class UpdateManager: ObservableObject {

    static let shared = UpdateManager()

    enum Phase: Equatable {
        case idle
        case available(ReleaseInfo)
        case downloading(Double)
        case installing
        case error(String)
    }

    /// 窗口内的更新流程状态(发现新版 → 下载 → 安装 → 出错)。
    @Published private(set) var phase: Phase = .idle
    /// 入口处的「检查中」状态。任何「检查更新」按钮都可观察它做内联 spinner。
    @Published private(set) var isChecking = false
    /// 最近一次检查发现的新版本，供设置页在检查行内显示更新入口。
    @Published private(set) var availableRelease: ReleaseInfo?

    private let service = UpdateService()
    private let attempts: UpdateAttemptService
    @Published private(set) var isInstalling = false
    private(set) var downloadPage: URL?
    private let logger = AppLogger(category: "UpdateManager")
    private(set) var window: NSWindow?
    private var windowDelegate: UpdateWindowDelegate?

    private var currentVersion: SemanticVersion? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return raw.flatMap(SemanticVersion.init)
    }

    init(attempts: UpdateAttemptService = UpdateAttemptService()) {
        self.attempts = attempts
    }

    // MARK: - 入口（可复用）

    func checkOnLaunch() {
        check(userInitiated: false)
    }

    /// Read only local state even when automatic update checks are disabled.
    func recoverInterruptedUpdate() async -> Bool {
        guard !isInstalling else { return false }
        do {
            guard let attempt = try await previousAttempt() else { return false }
            let result = try await attempts.result()
            let version = currentVersion?.raw ?? "unknown"
            let succeeded = UpdateAttemptService.succeeded(attempt: attempt, currentVersion: version, result: result)
            DiagnosticLogService.record(
                level: succeeded ? .info : .error,
                category: "update", action: succeeded ? "installCompleted" : "installInterrupted",
                fields: ["sourceVersion": attempt.sourceVersion, "targetVersion": attempt.targetVersion,
                         "currentVersion": version, "stage": attempt.stage, "reasonCode": result ?? "interrupted"]
            )
            await DiagnosticLogService.shared.flush()
            downloadPage = attempt.downloadPage
            if succeeded {
                ToastCenter.shared.show(message: "update.completed".localized(attempt.targetVersion),
                                        systemImage: "checkmark.circle.fill", tint: .green)
            } else {
                phase = .error("update.error.interrupted".localized(attempt.targetVersion, version))
                showUpdateWindow()
            }
            if Bundle.main.bundleURL.resolvingSymlinksInPath().path == attempt.bundlePath {
                do {
                    try await attempts.clear(removeBackup: succeeded)
                } catch {
                    // Cleanup cannot turn a confirmed successful installation into an update error.
                    logger.error("Update cleanup deferred: \(error.localizedDescription)")
                    await attempts.releaseOwnership()
                }
            } else {
                // A failed rollback may have opened the hidden backup. Keep the original
                // destination until manual recovery; this bundle cannot self-update in place.
                await attempts.releaseOwnership()
            }
            return true
        } catch {
            await attempts.releaseOwnership()
            logger.error("Update recovery failed: \(error.localizedDescription)")
            phase = .error("update.error.install".localized)
            showUpdateWindow()
            return true
        }
    }

    private func previousAttempt() async throws -> UpdateAttempt? {
        while !Task.isCancelled {
            do {
                return try await attempts.pending(for: Bundle.main.bundleURL)
            } catch UpdateAttemptService.AttemptError.busy {
                // Another app process or the detached installer still owns the files.
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        throw CancellationError()
    }

    /// 统一的「检查更新」入口。任何想加检查入口的地方都复用它:
    /// 先检查，发现新版或主动检查失败时显示窗口；已是最新版时显示轻量提示。
    func check(userInitiated: Bool) {
        DiagnosticLogService.record(
            category: "update",
            action: "checkRequested",
            fields: ["userInitiated": String(userInitiated)]
        )
        // 窗口已开（正在下载/安装等）→ 直接前置,不重复检查。
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard !isChecking else { return }
        isChecking = true
        Task {
            if await recoverInterruptedUpdate() {
                isChecking = false
                return
            }
            guard userInitiated || SettingsManager.shared.autoCheckUpdates else {
                isChecking = false
                return
            }
            do {
                // 通道由用户设置决定：开启「尝鲜 Beta」后自动/手动均纳入 prerelease；
                // 默认只走稳定的 releases/latest。
                let includeBeta = SettingsManager.shared.includeBetaUpdates
                let release = try await service.fetchLatest(includePrereleases: includeBeta)
                isChecking = false
                handle(release: release, userInitiated: userInitiated)
            } catch {
                isChecking = false
                logger.error("Update check failed: \(error.localizedDescription)")
                guard userInitiated else { return }
                phase = .error(error.localizedDescription)
                showUpdateWindow()
            }
        }
    }

    /// 用户点击「立即更新」。
    func startInstall(_ release: ReleaseInfo) {
        guard !isInstalling, !isChecking else { return }
        isInstalling = true
        downloadPage = release.htmlURL
        Task {
            var attemptStarted = false
            do {
                let destination = Bundle.main.bundleURL
                try await service.validateDestination(destination)
                try await attempts.begin(sourceVersion: currentVersion?.raw ?? "unknown", release: release, destination: destination)
                attemptStarted = true
                DiagnosticLogService.record(
                    category: "update", action: "installRequested",
                    fields: ["sourceVersion": currentVersion?.raw ?? "unknown", "targetVersion": release.tagName]
                )
                await DiagnosticLogService.shared.flush()
                phase = .downloading(0)
                let dmg = try await service.download(release) { [weak self] fraction in
                    guard let self else { return }
                    Task { @MainActor in
                        guard case .downloading = self.phase else { return }
                        self.phase = .downloading(fraction)
                    }
                }
                try await attempts.advance(to: "verifying")
                phase = .installing
                let staged = try await service.verifyAndStage(dmgURL: dmg, expectedVersion: release.version)
                try await attempts.staged(staged)
                let resultURL = await attempts.resultURL
                let ownership = try await attempts.installerOwnership()
                try await service.installAndRelaunch(
                    stagedApp: staged, destination: destination, resultURL: resultURL, ownership: ownership
                )
                await attempts.releaseOwnership()
                await DiagnosticLogService.shared.flush()
                // Do not trigger another SwiftUI layout after handing off the installer.
                NSApp.terminate(nil)
            } catch {
                phase = .error(error.localizedDescription)
                showUpdateWindow()
                DiagnosticLogService.record(
                    level: .error, category: "update", action: "installFailed",
                    fields: ["targetVersion": release.tagName, "reasonCode": String(describing: error)]
                )
                await DiagnosticLogService.shared.flush()
                if attemptStarted {
                    do { try await attempts.clear() } catch {
                        logger.error("Update receipt cleanup failed: \(error.localizedDescription)")
                    }
                }
                await attempts.releaseOwnership()
                logger.error("Update install failed: \(error.localizedDescription)")
                isInstalling = false
            }
        }
    }

    /// 从设置页重新打开已发现版本的更新窗口。
    func presentAvailableRelease() {
        guard !isInstalling, let availableRelease else { return }
        phase = .available(availableRelease)
        showUpdateWindow()
    }

    /// 关闭更新窗口，重置状态。
    func dismissWindow() {
        guard !isInstalling else { return }
        window?.orderOut(nil)
        window = nil
        windowDelegate = nil
        phase = .idle
    }

    /// 用户选择跳过此版本。
    func skipVersion(_ release: ReleaseInfo) {
        guard !isInstalling else { return }
        SettingsManager.shared.lastIgnoredVersion = release.tagName
        availableRelease = nil
        dismissWindow()
    }

    // MARK: - 内部

    func handle(release: ReleaseInfo, userInitiated: Bool) {
        guard let current = currentVersion, current < release.version else {
            availableRelease = nil
            guard userInitiated else { return }
            ToastCenter.shared.show(message: "update.upToDate.message".localized,
                                    systemImage: "checkmark.circle.fill", tint: .green)
            return
        }
        if !userInitiated, SettingsManager.shared.lastIgnoredVersion == release.tagName {
            return
        }
        availableRelease = release
        downloadPage = release.htmlURL
        phase = .available(release)
        showUpdateWindow()
    }

    // MARK: - 窗口

    private func showUpdateWindow() {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        let height = min(500, (NSScreen.main?.visibleFrame.height ?? 800) * 0.85)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 408, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "update.window.title".localized
        w.isReleasedWhenClosed = false
        // AppKit owns a stable frame. Content-driven resizing can recurse through
        // safe-area invalidation and abort the process on macOS 26 during phase changes.
        let hosting = NSHostingController(rootView: UpdateWindowView().environmentObject(self))
        hosting.sizingOptions = []
        w.contentViewController = hosting
        let delegate = UpdateWindowDelegate(canClose: { [weak self] in self?.isInstalling != true }) { [weak self] in
            self?.phase = .idle
            self?.window = nil
            self?.windowDelegate = nil
        }
        w.delegate = delegate
        windowDelegate = delegate
        // Cap hard max so even a preferred-size glitch can't push past the screen.
        if let screen = NSScreen.main {
            let maxH = screen.visibleFrame.height * 0.85
            w.maxSize = NSSize(width: 480, height: maxH)
        }
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Window Delegate

private final class UpdateWindowDelegate: NSObject, NSWindowDelegate {
    let canClose: () -> Bool
    let onClose: () -> Void
    init(canClose: @escaping () -> Bool, onClose: @escaping () -> Void) {
        self.canClose = canClose
        self.onClose = onClose
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { canClose() }
    func windowWillClose(_ notification: Notification) { onClose() }
}
