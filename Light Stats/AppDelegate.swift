//
//  AppDelegate.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import AppKit
import SwiftUI
import Combine

/// 无标题栏的浮动面板默认 `canBecomeKey` 返回 false，导致 `makeKeyAndOrderFront`
/// 无法设为 key window（控制台报 makeKeyWindow 警告），且配合 `hidesOnDeactivate`
/// 会在激活时立刻被隐藏。重写这两个属性以允许面板成为 key/main window。
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// 面板失去 key 焦点（点击外部 / 切换到别的菜单栏图标）时回调。
    /// 复刻 NSPopover .transient 的自动关闭行为，参考 Maccy 的 FloatingPanel。
    var onResignKey: (() -> Void)?

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var aboutWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var statusBarView: StatusBarView?
    // 面板因失去 key 焦点自动关闭的时刻，用于在点击图标关闭时避免立即重开
    private var panelAutoClosedAt: Date?
    // 面板打开时监听面板外的全局点击（含别的菜单栏图标），点外部即关闭
    private var globalClickMonitor: Any?

    private let settings: SettingsManager
    private let monitor: SystemMonitor
    private let appMemoryManager: AppMemoryManager
    private let scrollService: ScrollReversing

    override init() {
        self.settings = SettingsManager.shared
        self.monitor = SystemMonitor.shared
        self.appMemoryManager = AppMemoryManager.shared
        self.scrollService = ScrollDirectionService()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        startMonitoring()
        // 触发清洁模式遮罩控制器的惰性初始化，使其开始监听 isActive。
        _ = CleaningModeOverlayController.shared

        // 滚动方向翻转：监听开关变化
        settings.$scrollReverseEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.startScrollServiceOrPrompt()
                } else {
                    self.scrollService.stop()
                }
            }
            .store(in: &cancellables)

        // 启动时若已启用，尝试启动服务
        if settings.scrollReverseEnabled {
            startScrollServiceOrPrompt()
        }

        // 应用回到前台时复查权限（用户可能已授权但之前 tap 创建失败）。
        // 权限已满足且开关开启但服务未运行时自动启动。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowAbout),
            name: .showAbout,
            object: nil
        )

        // 启动后延迟检查更新，避开冷启动高峰；尊重「自动检查」开关。
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            UpdateManager.shared.checkOnLaunch()
        }
    }

    @objc private func handleShowAbout() {
        showAbout()
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        // Calculate initial width based on enabled items
        let initialWidth = StatusBarView.calculateWidth(settings: settings)

        statusItem = NSStatusBar.system.statusItem(withLength: initialWidth)

        if let button = statusItem?.button {
            // Create custom status bar view
            let view = StatusBarView(frame: NSRect(x: 0, y: 0, width: initialWidth, height: 22))
            statusBarView = view
            button.addSubview(view)
            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]

            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 780),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        // 自动关闭交给 resignKey 处理（见 onResignKey），无需 hidesOnDeactivate。
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = NSHostingController(
            rootView: PopoverContentView()
                .environmentObject(monitor)
                .environmentObject(AIUsageMonitor.shared)
        )

        // 失去 key 焦点（点击外部 / 切换到别的菜单栏图标）时自动关闭，
        // 复刻 NSPopover .transient 行为，无需再次点击图标手动隐藏。
        panel.onResignKey = { [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.dismissPanel(autoClosed: true)
        }

        self.panel = panel
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.startMonitoring(interval: settings.refreshRate.interval)
        // 不在启动时常驻开启 appMemoryManager：其全进程扫描（ps -axo + 每进程
        // proc_pidpath / responsibility 查询，每 5s 一次）仅服务于 Cleanup 标签页。
        // 改为在面板打开时预热（见 togglePanel），面板关闭即停（见 dismissPanel），
        // 既消除了面板从未打开时的后台白扫，又保证首次切到 Cleanup 页数据已就绪、不闪空态。
        if settings.aiMonitorClaudeEnabled || settings.aiMonitorCodexEnabled || settings.aiMonitorGeminiEnabled {
            AIUsageMonitor.shared.start()
        }

        // 监听刷新频率变化，重新启动监控
        settings.$refreshRate
            .dropFirst()  // 跳过初始值
            .receive(on: DispatchQueue.main)
            .sink { [weak monitor = self.monitor] newRate in
                monitor?.startMonitoring(interval: newRate.interval)
            }
            .store(in: &cancellables)

        // Update status bar text when values change
        Publishers.CombineLatest4(
            monitor.$cpuUsage,
            monitor.$gpuUsage,
            monitor.$memoryUsage,
            monitor.$diskAvailable
        )
        .combineLatest(
            Publishers.CombineLatest3(
                monitor.$networkUpload,
                monitor.$networkDownload,
                monitor.$fanSpeed
            )
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] values in
            let (main, network) = values
            let (cpu, gpu, memory, disk) = main
            let (upload, download, fan) = network
            self?.updateStatusBarText(
                cpu: cpu,
                gpu: gpu,
                memory: memory,
                disk: disk,
                upload: upload,
                download: download,
                fan: fan
            )
        }
        .store(in: &cancellables)
    }

    private func updateStatusBarText(
        cpu: Double,
        gpu: Double?,
        memory: Double,
        disk: UInt64,
        upload: Double,
        download: Double,
        fan: Int?
    ) {
        // Update status bar view（电池随每周期刷新，直接从 monitor 取最新值）
        statusBarView?.updateValues(
            cpu: cpu,
            gpu: gpu,
            memory: memory,
            disk: disk,
            upload: upload,
            download: download,
            fan: fan,
            battery: monitor.battery,
            health: monitor.health,
            settings: settings
        )

        // Update status item width
        let newWidth = StatusBarView.calculateWidth(settings: settings)
        statusItem?.length = newWidth
        statusBarView?.frame.size.width = newWidth
    }

    // MARK: - Actions

    func closePanel() {
        dismissPanel()
    }

    /// 统一关闭面板：隐藏、同步状态、停止采集、移除全局点击监听。
    private func dismissPanel(autoClosed: Bool = false) {
        panel?.orderOut(nil)
        if autoClosed { panelAutoClosedAt = Date() }
        monitor.setPopoverVisible(false)
        appMemoryManager.stopMonitoring()
        removeGlobalClickMonitor()
    }

    /// 面板打开期间监听面板外的全局点击（点桌面、点别的菜单栏图标等）并关闭面板。
    /// 自身状态栏按钮/面板内部的点击是本进程本地事件，不会被全局监听捕获，因此不受影响。
    private func installGlobalClickMonitor() {
        removeGlobalClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.dismissPanel(autoClosed: true)
        }
    }

    private func removeGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    // MARK: - About Window

    @objc func showAbout() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(
            rootView: AboutView()
        )

        aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePanel() {
        guard let panel = panel, let button = statusItem?.button else { return }

#if DEBUG
        // 按住 ⌥ Option 点击图标：导出面板完整内容截图到 /tmp，不打开面板。
        if NSEvent.modifierFlags.contains(.option) {
            DebugSnapshot.dumpPanel()
            return
        }
#endif

        if panel.isVisible {
            dismissPanel()
            return
        }

        // 若面板刚因 resignKey 自动关闭（点击图标时会先失去 key 焦点），
        // 则把这次点击视为"关闭"，不要立即重新打开。
        if let closedAt = panelAutoClosedAt, Date().timeIntervalSince(closedAt) < 0.25 {
            panelAutoClosedAt = nil
            return
        }

        guard let buttonWindow = button.window else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)

        let panelSize = panel.frame.size
        let panelOrigin = NSPoint(
            x: buttonRectOnScreen.midX - (panelSize.width / 2),
            y: buttonRectOnScreen.minY - panelSize.height - 6
        )

        panel.setFrameOrigin(panelOrigin)
        AIUsageMonitor.shared.refreshIfStale()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor.setPopoverVisible(true)
        // 面板一打开即预热进程内存扫描，用户从 Overview 切到 Cleanup 时数据已就绪。
        // Cleanup 页的 onAppear/onDisappear 仍会幂等地接管 start/stop。
        appMemoryManager.startMonitoring()
        installGlobalClickMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stopMonitoring()
        appMemoryManager.stopMonitoring()
        AIUsageMonitor.shared.stop()
        scrollService.stop()
        SMCInfo.shutdown()
    }

    // MARK: - Scroll Direction

    /// 尝试启动滚动方向翻转服务。若 tap 创建失败（缺少 Accessibility 权限），
    /// 弹出权限引导对话框；保持开关开启，待用户授权后前台激活时自动重试。
    private func startScrollServiceOrPrompt() {
        guard !scrollService.isRunning else { return }

        if scrollService.start() {
            return
        }

        // 权限不足：先不带弹窗检测一次状态
        guard scrollService.checkPermission(promptIfNeeded: false) else {
            presentScrollPermissionAlert()
            return
        }

        // 权限已满足但 tap 创建仍失败（罕见：其他系统问题）→ 静默，开关保持 on
    }

    @objc private func handleAppDidBecomeActive() {
        guard settings.scrollReverseEnabled, !scrollService.isRunning else { return }
        _ = scrollService.start()
    }

    private func presentScrollPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "settings.scrollReverse.permissionTitle".localized
        alert.informativeText = "settings.scrollReverse.permissionMessage".localized
        alert.addButton(withTitle: "cleaning.permission.openSettings".localized)
        alert.addButton(withTitle: "update.action.later".localized)
        if alert.runModal() == .alertFirstButtonReturn {
            guard let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }
}
