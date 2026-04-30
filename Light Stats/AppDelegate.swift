//
//  AppDelegate.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import AppKit
import SwiftUI
import Combine

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
        let panel = NSPanel(
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
        )

        self.panel = panel
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.startMonitoring(interval: settings.refreshRate.interval)
        appMemoryManager.startMonitoring()

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
        // Update status bar view
        statusBarView?.updateValues(
            cpu: cpu,
            gpu: gpu,
            memory: memory,
            disk: disk,
            upload: upload,
            download: download,
            fan: fan,
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
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stopMonitoring()
        appMemoryManager.stopMonitoring()
    }
}
