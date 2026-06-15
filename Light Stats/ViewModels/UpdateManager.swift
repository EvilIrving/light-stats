//
//  UpdateManager.swift
//  Light Stats
//
//  自动更新的 UI 协调层（@MainActor）。负责：版本比对、弹窗提示、驱动下载/校验/
//  安装的进度，以及失败兜底（打开 Release 页面）。系统数据层在 UpdateService。
//
//  用户的唯一操作是点「立即更新」——之后下载、校验、替换、重启全自动完成。
//

import AppKit
import SwiftUI
import Combine
import os

@MainActor
final class UpdateManager: ObservableObject {

    static let shared = UpdateManager()

    /// 更新流程阶段。进度面板与 About 按钮根据它渲染。
    enum Phase: Equatable {
        case idle
        case checking
        case downloading(Double)
        case installing
    }

    @Published private(set) var phase: Phase = .idle

    private let service = UpdateService()
    private let logger = Logger(subsystem: "com.lightstats", category: "UpdateManager")
    private var progressWindow: NSWindow?

    private var currentVersion: SemanticVersion? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return raw.flatMap(SemanticVersion.init)
    }

    private init() {}

    // MARK: - 入口

    /// 启动时调用：仅当用户开启自动检查时才静默检查，且尊重「忽略此版本」。
    func checkOnLaunch() {
        guard SettingsManager.shared.autoCheckUpdates else { return }
        checkForUpdates(userInitiated: false)
    }

    /// 检查更新。`userInitiated` 为手动点击：会无视「忽略」记录，并在已是最新/出错时给出反馈。
    func checkForUpdates(userInitiated: Bool) {
        guard phase == .idle else { return }
        phase = .checking
        Task {
            do {
                let release = try await service.fetchLatest()
                phase = .idle
                handle(release: release, userInitiated: userInitiated)
            } catch {
                phase = .idle
                logger.error("Update check failed: \(error.localizedDescription)")
                if userInitiated { presentError(message: error.localizedDescription, release: nil) }
            }
        }
    }

    // MARK: - 版本比对

    private func handle(release: ReleaseInfo, userInitiated: Bool) {
        guard let current = currentVersion, current < release.version else {
            if userInitiated { presentUpToDate() }
            return
        }
        if !userInitiated, SettingsManager.shared.lastIgnoredVersion == release.tagName {
            return  // 用户已忽略该版本，自动检查时跳过。
        }
        presentAvailable(release)
    }

    // MARK: - 弹窗：发现新版本

    private func presentAvailable(_ release: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "update.available.title".localized(release.tagName)
        alert.informativeText = release.releaseNotes.isEmpty
            ? "update.available.message".localized
            : release.releaseNotes
        alert.addButton(withTitle: "update.action.install".localized)
        alert.addButton(withTitle: "update.action.later".localized)
        alert.addButton(withTitle: "update.action.skip".localized)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            startInstall(release)
        case .alertThirdButtonReturn:
            SettingsManager.shared.lastIgnoredVersion = release.tagName
        default:
            break  // 稍后：什么都不做，下次检查再提示。
        }
    }

    // MARK: - 下载 + 校验 + 安装

    private func startInstall(_ release: ReleaseInfo) {
        phase = .downloading(0)
        showProgressWindow()
        Task {
            do {
                let dmg = try await service.download(release) { [weak self] fraction in
                    Task { @MainActor in self?.phase = .downloading(fraction) }
                }
                phase = .installing
                let destination = Bundle.main.bundleURL
                let staged = try await service.verifyAndStage(dmgURL: dmg)
                try await service.installAndRelaunch(stagedApp: staged, destination: destination)
                // 替换脚本已接管，退出当前进程让它完成覆盖并重启。
                NSApp.terminate(nil)
            } catch {
                closeProgressWindow()
                phase = .idle
                logger.error("Update install failed: \(error.localizedDescription)")
                presentError(message: error.localizedDescription, release: release)
            }
        }
    }

    // MARK: - 弹窗：已是最新 / 出错

    private func presentUpToDate() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "update.upToDate.title".localized
        alert.informativeText = "update.upToDate.message".localized
        alert.addButton(withTitle: "update.action.ok".localized)
        alert.runModal()
    }

    private func presentError(message: String, release: ReleaseInfo?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "update.error.title".localized
        alert.informativeText = message
        alert.addButton(withTitle: "update.action.openPage".localized)
        alert.addButton(withTitle: "update.action.ok".localized)
        if alert.runModal() == .alertFirstButtonReturn {
            let fallback = URL(string: "https://github.com/\(UpdateService.repo)/releases/latest")
            if let url = release?.htmlURL ?? fallback {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - 进度窗口

    private func showProgressWindow() {
        if progressWindow != nil { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        window.contentViewController = NSHostingController(rootView: UpdateProgressView(manager: self))
        progressWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeProgressWindow() {
        progressWindow?.orderOut(nil)
        progressWindow = nil
    }
}
