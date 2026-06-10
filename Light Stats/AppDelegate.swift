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
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var aboutWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var statusBarView: StatusBarView?
    
    private let settings: SettingsManager
    private let monitor: SystemMonitor
    private let appMemoryManager: AppMemoryManager
    
    override init() {
        self.settings = SettingsManager.shared
        self.monitor = SystemMonitor.shared
        self.appMemoryManager = AppMemoryManager.shared
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        startMonitoring()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowAbout),
            name: .showAbout,
            object: nil
        )
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
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = true
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

        // 面板因 hidesOnDeactivate 自动隐藏时不会经过 togglePanel/closePanel，
        // 监听 resignKey 兜底同步可见状态，确保关闭后停止采集进程榜。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePanelDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )

        self.panel = panel
    }

    @objc private func handlePanelDidResignKey() {
        monitor.setPopoverVisible(panel?.isVisible ?? false)
        if panel?.isVisible != true {
            appMemoryManager.stopMonitoring()
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.startMonitoring(interval: settings.refreshRate.interval)
        appMemoryManager.startMonitoring()
        if settings.aiMonitorClaudeEnabled || settings.aiMonitorCodexEnabled {
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
        panel?.orderOut(nil)
        monitor.setPopoverVisible(false)
        appMemoryManager.stopMonitoring()
    }

    // MARK: - About Window

    @objc func showAbout() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 330),
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

        if panel.isVisible {
            panel.orderOut(nil)
            monitor.setPopoverVisible(false)
            appMemoryManager.stopMonitoring()
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stopMonitoring()
        appMemoryManager.stopMonitoring()
        AIUsageMonitor.shared.stop()
    }
}
