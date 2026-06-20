//
//  UpdateManager.swift
//  Light Stats
//
//  更新协调层（@MainActor）。`check(userInitiated:)` 是统一、可复用的入口:
//  先静默检查 → 仅当发现新版本时才弹出更新窗口;无新版/出错时(用户主动触发)
//  只弹一个轻量提示框,不进窗口。检查中状态由 `isChecking` 暴露给入口处内联展示。
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

    private let service = UpdateService()
    private let logger = Logger(subsystem: "com.lightstats", category: "UpdateManager")
    private var window: NSWindow?
    private var windowDelegate: UpdateWindowDelegate?

    private var currentVersion: SemanticVersion? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return raw.flatMap(SemanticVersion.init)
    }

    private init() {}

    // MARK: - 入口（可复用）

    func checkOnLaunch() {
        guard SettingsManager.shared.autoCheckUpdates else { return }
        check(userInitiated: false)
    }

    /// 统一的「检查更新」入口。任何想加检查入口的地方都复用它:
    /// 先检查,发现新版才弹窗;无新版/出错仅在用户主动触发时弹轻量提示。
    func check(userInitiated: Bool) {
        // 窗口已开（正在下载/安装等）→ 直接前置,不重复检查。
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard !isChecking else { return }
        isChecking = true
        Task {
            do {
                let release = try await service.fetchLatest()
                isChecking = false
                handle(release: release, userInitiated: userInitiated)
            } catch {
                isChecking = false
                logger.error("Update check failed: \(error.localizedDescription)")
                guard userInitiated else { return }
                ToastCenter.shared.show(message: "update.error.title".localized,
                                        systemImage: "exclamationmark.triangle.fill", tint: .orange)
            }
        }
    }

    /// 用户点击「立即更新」。
    func startInstall(_ release: ReleaseInfo) {
        phase = .downloading(0)
        Task {
            do {
                let dmg = try await service.download(release) { [weak self] fraction in
                    Task { @MainActor in self?.phase = .downloading(fraction) }
                }
                phase = .installing
                let destination = Bundle.main.bundleURL
                let staged = try await service.verifyAndStage(dmgURL: dmg)
                try await service.installAndRelaunch(stagedApp: staged, destination: destination)
                NSApp.terminate(nil)
            } catch {
                phase = .error(error.localizedDescription)
                logger.error("Update install failed: \(error.localizedDescription)")
            }
        }
    }

    /// 关闭更新窗口，重置状态。
    func dismissWindow() {
        window?.orderOut(nil)
        window = nil
        windowDelegate = nil
        phase = .idle
    }

    /// 用户选择跳过此版本。
    func skipVersion(_ release: ReleaseInfo) {
        SettingsManager.shared.lastIgnoredVersion = release.tagName
        dismissWindow()
    }

    // MARK: - 内部

    private func handle(release: ReleaseInfo, userInitiated: Bool) {
        guard let current = currentVersion, current < release.version else {
            guard userInitiated else { return }
            ToastCenter.shared.show(message: "update.upToDate.message".localized,
                                    systemImage: "checkmark.circle.fill", tint: .green)
            return
        }
        if !userInitiated, SettingsManager.shared.lastIgnoredVersion == release.tagName {
            return
        }
        phase = .available(release)
        showUpdateWindow()
    }

    // MARK: - 窗口

    private func showUpdateWindow() {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "update.window.title".localized
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        // 固定宽度、高度随内容动态:.preferredContentSize 让窗口跟随 SwiftUI 内容
        // 尺寸变化(发现新版 → 下载 → 安装)自动收放,无需 ScrollView。
        let hosting = NSHostingController(rootView: UpdateWindowView().environmentObject(self))
        hosting.sizingOptions = [.preferredContentSize]
        w.contentViewController = hosting
        let delegate = UpdateWindowDelegate { [weak self] in
            self?.phase = .idle
            self?.window = nil
            self?.windowDelegate = nil
        }
        w.delegate = delegate
        windowDelegate = delegate
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Window Delegate

private final class UpdateWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
