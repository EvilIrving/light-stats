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

/// Keeps mouse / scroll events inside the popover when SwiftUI has no painted
/// descendant at a point. Real controls and scroll views keep normal hit targets.
/// Unhandled `scrollWheel` is absorbed so a non-opaque panel does not forward
/// wheel events through to the desktop (macOS 26). Does not paint or change colors.
final class HitRetainingHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) ?? (bounds.contains(point) ? self : nil)
    }

    override func scrollWheel(with _: NSEvent) {
        // Descendants that handle scrolling receive the event via hit-testing.
        // Anything that lands here must not continue past this panel.
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    private var statusItem: NSStatusItem?
    private var windowControlsStatusItem: NSStatusItem?
    private var panel: NSPanel?
    private var aboutWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var statusBarView: StatusBarView?
    // 面板因失去 key 焦点自动关闭的时刻，用于在点击图标关闭时避免立即重开
    private var panelAutoClosedAt: Date?
    // 面板打开时监听面板外的全局点击（含别的菜单栏图标），点外部即关闭
    private var globalClickMonitor: Any?
    private var windowControlPermissionAlertShown = false
    private var terminationInProgress = false
    private var terminationReplySent = false

    private let settings: SettingsManager
    private let monitor: SystemMonitor
    private let appMemoryManager: AppMemoryManager
    private let scrollService: ScrollReversing
    private let windowSnappingService: WindowSnappingService
    private let magnetHotKeyService: MagnetHotKeyControlling
    private let titlebarGestureService: TitlebarGestureControlling
    private static let windowMenuActions: [(tag: Int, action: WindowSnapAction)] = [
        (1, .leftHalf), (2, .rightHalf), (3, .topHalf), (4, .bottomHalf),
        (5, .topLeft), (6, .topRight), (7, .bottomLeft), (8, .bottomRight),
        (9, .leftThird), (10, .leftTwoThirds), (11, .centerThird),
        (12, .rightTwoThirds), (13, .rightThird),
        (14, .previousDisplay), (15, .nextDisplay),
        (16, .maximize), (17, .center), (18, .restore), (19, .minimize)
    ]

    override init() {
        self.settings = SettingsManager.shared
        self.monitor = SystemMonitor.shared
        self.appMemoryManager = AppMemoryManager.shared
        self.scrollService = ScrollDirectionService()
        let windowSnappingService = WindowSnappingService()
        self.windowSnappingService = windowSnappingService
        self.magnetHotKeyService = MagnetHotKeyService(snappingService: windowSnappingService)
        self.titlebarGestureService = TitlebarGestureService(snappingService: windowSnappingService)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        recordApplicationLaunch()
        // Create the monitoring item first: macOS parks each newly-created status item to the
        // left of the previous one, so creating the monitor first and the window-controls item
        // second places the split-screen icon to the RIGHT of the monitoring numbers by default.
        // The window-controls item is created lazily by syncWindowControlServices() below, and
        // only when windowManagementEnabled is on — pure-monitoring users never see it.
        setupStatusItem()
        setupPanel()
        startMonitoring()
        // 触发清洁模式遮罩控制器的惰性初始化，使其开始监听 isActive。
        _ = CleaningModeOverlayController.shared

        // 滚动处理：垂直反转 / 水平反转 / 步长倍率任一变更都重新同步服务。
        let scrollPublishers: [AnyPublisher<Void, Never>] = [
            settings.$scrollReverseEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$scrollReverseHorizontalEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$scrollStepMultiplier.map { _ in () }.eraseToAnyPublisher()
        ]
        for publisher in scrollPublishers {
            publisher
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.syncScrollService() }
                .store(in: &cancellables)
        }

        // 窗口管理总开关：单一开关同时驱动菜单栏图标、快捷键、标题栏手势的起停。
        settings.$windowManagementEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.windowControlPermissionAlertShown = false
                self?.syncWindowControlServices()
            }
            .store(in: &cancellables)

        // Finder 右键菜单总开关：开 → 注册宿主 CFMessagePort；关 → 注销。
        settings.$finderMenuEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncFinderMenuService() }
            .store(in: &cancellables)

        // 保持唤醒总开关：开 → 持有 IOPM 断言阻止息屏；关 → 释放。
        settings.$keepAwakeEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncKeepAwakeService() }
            .store(in: &cancellables)

        // Finder 菜单本地化标题：语言变更时重新发布到 App Group 供扩展读取。
        settings.$appLanguage
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { _ in FinderMenuHostService.shared.publishLabels() }
            .store(in: &cancellables)

        // 启动时按当前设置同步一次（推送配置 + 决定是否启动 tap）。
        syncScrollService()
        syncWindowControlServices()
        syncFinderMenuService()
        syncKeepAwakeService()
        // 启动即发布一次本地化标题，确保扩展冷启动就能读到当前语言的菜单文案。
        FinderMenuHostService.shared.publishLabels()

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFinderMenuActionFailed(_:)),
            name: .finderMenuActionFailed,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFinderMenuFilePanelWillPresent),
            name: .finderMenuFilePanelWillPresent,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFinderMenuFilePanelDidDismiss),
            name: .finderMenuFilePanelDidDismiss,
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

    @objc private func handleFinderMenuActionFailed(_ notification: Notification) {
        let message = notification.userInfo?["message"] as? String ?? "findermenu.toast.actionFailed".localized
        ToastCenter.shared.show(message: message, systemImage: "exclamationmark.triangle.fill", tint: .orange, duration: 3)
    }

    @objc private func handleFinderMenuFilePanelWillPresent() {
        scrollService.setSuspended(true)
        titlebarGestureService.setSuspended(true)
    }

    @objc private func handleFinderMenuFilePanelDidDismiss() {
        scrollService.setSuspended(false)
        titlebarGestureService.setSuspended(false)
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
            // Kept in the button's view hierarchy so its CADisplayLink (fan spin) fires; it no
            // longer draws on screen — it renders a template image into button.image instead.
            button.addSubview(view)
            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]
            button.imagePosition = .imageOnly
            view.attach(to: button)

            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    // MARK: - Window Controls Status Item

    /// 仅当窗口管理开启时创建菜单栏图标；已存在则幂等返回。
    private func ensureWindowControlsStatusItem() {
        guard windowControlsStatusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "settings.windowControls".localized)
            button.image?.isTemplate = true
        }
        item.menu = makeWindowControlsMenu()
        windowControlsStatusItem = item
    }

    /// 关闭窗口管理时彻底移除图标（而非仅隐藏），不留菜单栏占位。
    private func removeWindowControlsStatusItem() {
        guard let item = windowControlsStatusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        windowControlsStatusItem = nil
    }

    private func makeWindowControlsMenu() -> NSMenu {
        let menu = NSMenu()
        addWindowMenuItem("window.action.left".localized, action: .leftHalf, key: "←", to: menu)
        addWindowMenuItem("window.action.right".localized, action: .rightHalf, key: "→", to: menu)
        addWindowMenuItem("window.action.top".localized, action: .topHalf, key: "↑", to: menu)
        addWindowMenuItem("window.action.bottom".localized, action: .bottomHalf, key: "↓", to: menu)
        menu.addItem(.separator())
        addWindowMenuItem("window.action.topLeft".localized, action: .topLeft, to: menu)
        addWindowMenuItem("window.action.topRight".localized, action: .topRight, to: menu)
        addWindowMenuItem("window.action.bottomLeft".localized, action: .bottomLeft, to: menu)
        addWindowMenuItem("window.action.bottomRight".localized, action: .bottomRight, to: menu)
        menu.addItem(.separator())
        addWindowMenuItem("window.action.leftThird".localized, action: .leftThird, to: menu)
        addWindowMenuItem("window.action.leftTwoThirds".localized, action: .leftTwoThirds, to: menu)
        addWindowMenuItem("window.action.centerThird".localized, action: .centerThird, to: menu)
        addWindowMenuItem("window.action.rightTwoThirds".localized, action: .rightTwoThirds, to: menu)
        addWindowMenuItem("window.action.rightThird".localized, action: .rightThird, to: menu)
        menu.addItem(.separator())
        addWindowMenuItem(
            "window.action.previousDisplay".localized,
            action: .previousDisplay,
            to: menu
        )
        addWindowMenuItem(
            "window.action.nextDisplay".localized,
            action: .nextDisplay,
            to: menu
        )
        menu.addItem(.separator())
        addWindowMenuItem("window.action.maximize".localized, action: .maximize, to: menu)
        addWindowMenuItem("window.action.center".localized, action: .center, to: menu)
        addWindowMenuItem("window.action.restore".localized, action: .restore, to: menu)
        return menu
    }

    private func addWindowMenuItem(
        _ title: String,
        action: WindowSnapAction,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.control, .option],
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: #selector(performWindowMenuAction(_:)), keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.tag = tag(for: action)
        item.image = WindowSnapIconProvider.icon(for: action)
        menu.addItem(item)
    }

    @objc private func performWindowMenuAction(_ sender: NSMenuItem) {
        guard let action = action(for: sender.tag) else { return }
        windowSnappingService.perform(action)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performWindowMenuAction(_:)) else { return true }
        guard let action = action(for: menuItem.tag) else { return false }
        return windowSnappingService.canPerform(action)
    }

    private func tag(for action: WindowSnapAction) -> Int {
        Self.windowMenuActions.first { $0.action == action }?.tag ?? 0
    }

    private func action(for tag: Int) -> WindowSnapAction? {
        Self.windowMenuActions.first { $0.tag == tag }?.action
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        let canvasSize = PopoverContentView.canvasSize
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: canvasSize),
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
        panel.ignoresMouseEvents = false
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = HitRetainingHostingView(
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
        // 始终 start()：仅建立设置订阅，无 provider 开启时不发请求、不弹 Keychain（见
        // AIUsageMonitor 注释）。这样用户在运行期才开启某 provider 也能即时生效，
        // 且 warmup 自动续期依赖监控发布的窗口快照拿 reset 时间。
        AIUsageMonitor.shared.start()
        UsageWarmupManager.shared.start()

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

    /// 统一关闭面板：隐藏、同步状态、停止采集、移除全局点击监听。
    private func dismissPanel(autoClosed: Bool = false) {
        recordPanelClosed(automatically: autoClosed)
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
        DiagnosticLogService.record(category: "about", action: "opened")
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
        DiagnosticLogService.record(category: "popover", action: "opened")
        AIUsageMonitor.shared.refreshIfStale()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor.setPopoverVisible(true)
        // 面板一打开即预热进程内存扫描，用户从 Overview 切到 Cleanup 时数据已就绪。
        // Cleanup 页的 onAppear/onDisappear 仍会幂等地接管 start/stop。
        appMemoryManager.startMonitoring()
        installGlobalClickMonitor()
    }

    // MARK: - Keep Awake

    /// 保持唤醒服务的起停：开 → 持有 IOPM 电源断言阻止显示器息屏；关 → 释放断言。
    private func syncKeepAwakeService() {
        if settings.keepAwakeEnabled {
            KeepAwakeService.shared.start()
        } else {
            KeepAwakeService.shared.stop()
        }
    }

    // MARK: - Finder Menu

    /// Finder 右键菜单宿主服务的起停。总开关开 → 注册 CFMessagePort 接收扩展委派的动作；
    /// 关 → 注销端口。扩展侧由 FinderMenuShared.isEnabled() 独立把关，两道门都默认关。
    private func syncFinderMenuService() {
        FinderMenuShared.setEnabled(settings.finderMenuEnabled)
        if settings.finderMenuEnabled {
            FinderMenuHostService.shared.publishLabels()
            FinderMenuHostService.shared.start()
        } else {
            FinderMenuHostService.shared.stop()
        }
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
        if settings.scrollReverseEnabled || settings.scrollReverseHorizontalEnabled, !scrollService.isRunning {
            scrollService.updateConfig(currentScrollConfig())
            _ = scrollService.start()
        }
        syncWindowControlServices()
        if settings.finderMenuEnabled {
            syncFinderMenuService()
            FinderMenuConfigStore.shared.refreshExtensionStatus()
        }
    }

    private func currentScrollConfig() -> ScrollConfig {
        ScrollConfig(
            reverseVertical: settings.scrollReverseEnabled,
            reverseHorizontal: settings.scrollReverseHorizontalEnabled,
            stepMultiplier: settings.scrollStepMultiplier
        )
    }

    /// 窗口管理总开关统一驱动：开 → 图标 + 快捷键 + 手势全起；关 → 三者一起停。
    private func syncWindowControlServices() {
        if settings.windowManagementEnabled {
            ensureWindowControlsStatusItem()
            startMagnetHotKeysOrPrompt()
            startTitlebarGesturesOrPrompt()
        } else {
            magnetHotKeyService.stop()
            titlebarGestureService.stop()
            removeWindowControlsStatusItem()
        }
    }

    private func startMagnetHotKeysOrPrompt() {
        guard !magnetHotKeyService.isRunning else { return }
        if magnetHotKeyService.start() { return }
        presentWindowControlPermissionAlert()
    }

    private func startTitlebarGesturesOrPrompt() {
        guard !titlebarGestureService.isRunning else { return }
        if titlebarGestureService.start() { return }
        presentWindowControlPermissionAlert()
    }

    /// 同步滚动服务：热更新配置；按「垂直∨水平反转」决定 tap 起停。步长倍率依附
    /// 反转开关 —— 仅在 tap 运行时生效，单独调整倍率不会启动 tap。
    private func syncScrollService() {
        let config = currentScrollConfig()
        scrollService.updateConfig(config)
        if config.reverseVertical || config.reverseHorizontal {
            startScrollServiceOrPrompt()
        } else {
            scrollService.stop()
        }
    }

    private func presentScrollPermissionAlert() {
        presentAccessibilityAlert(
            title: "settings.scrollReverse.permissionTitle".localized,
            message: "settings.scrollReverse.permissionMessage".localized
        )
    }

    private func presentWindowControlPermissionAlert() {
        guard !windowControlPermissionAlertShown else { return }
        windowControlPermissionAlertShown = true
        presentAccessibilityAlert(
            title: "settings.windowControl.permissionTitle".localized,
            message: "settings.windowControl.permissionMessage".localized
        )
    }

    private func presentAccessibilityAlert(title: String, message: String) {
        AccessibilityPermission.presentSettingsAlert(title: title, message: message)
    }
}

extension AppDelegate {
    func closePanel() {
        dismissPanel()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationInProgress else { return .terminateLater }
        terminationInProgress = true
        DiagnosticLogService.record(category: "application", action: "willTerminate")
        stopRuntimeServices()

        Task { @MainActor [weak self] in
            await DiagnosticLogService.shared.close()
            self?.replyToTerminationIfNeeded(sender)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.replyToTerminationIfNeeded(sender)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRuntimeServices()
    }

    private func stopRuntimeServices() {
        monitor.stopMonitoring()
        appMemoryManager.stopMonitoring()
        AIUsageMonitor.shared.stop()
        UsageWarmupManager.shared.stopAll()
        scrollService.stop()
        magnetHotKeyService.stop()
        titlebarGestureService.stop()
        FinderMenuHostService.shared.stop()
        KeepAwakeService.shared.stop()
        SMCInfo.shutdown()
    }

    private func replyToTerminationIfNeeded(_ sender: NSApplication) {
        guard !terminationReplySent else { return }
        terminationReplySent = true
        sender.reply(toApplicationShouldTerminate: true)
    }
}

private extension AppDelegate {
    func recordApplicationLaunch() {
        DiagnosticLogService.record(
            category: "application",
            action: "launched",
            fields: [
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            ]
        )
    }

    func recordPanelClosed(automatically: Bool) {
        DiagnosticLogService.record(
            category: "popover",
            action: "closed",
            fields: ["automatic": String(automatically)]
        )
    }
}
