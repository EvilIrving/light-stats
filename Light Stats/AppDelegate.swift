//
//  AppDelegate.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    // 菜单栏窗口控制图标及其菜单见 AppDelegate+WindowMenu.swift。
    var windowControlsStatusItem: NSStatusItem?
    var panel: NSPanel?
    private var aboutWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var statusBarView: StatusBarView?
    // 面板因失去 key 焦点自动关闭的时刻，用于在点击图标关闭时避免立即重开
    private var panelAutoClosedAt: Date?
    // 面板打开时监听面板外点击：全局（其他 App）+ 本地（本进程其它窗口）。
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    // 面板打开期间最近一次「面板外鼠标按下」时刻；用于区分 resignKey 是否由点外部引起
    var lastGlobalMouseDownAt: Date?
    /// 刚关掉后仍保留，供点菜单栏时区分「关掉」还是「移回图标下方」。
    private var panelAnchor: PanelAnchor?
    private var windowControlPermissionAlertShown = false
    // 用户原本所在的前台 App。原生分屏必须作用在它的窗口上，而打开我们自己的菜单会抢走前台。
    var lastExternalApplicationPID: pid_t?

    let settings: SettingsManager
    private let monitor: SystemMonitor
    private let displayControlManager: DisplayControlManager
    let appMemoryManager: AppMemoryManager
    let scrollService: ScrollReversing
    let windowSnappingService: WindowSnappingService
    let windowSnapPreview: WindowSnapPreviewService
    let windowDragMonitorService: WindowDragMonitoring
    let snapIslandController: SnapIslandController
    let windowThumbnailService: WindowThumbnailService
    let windowPreviewIndex: WindowPreviewIndex
    let dockHoverMonitor: DockHoverMonitoring
    let dockPreviewController: DockPreviewController
    let appSwitcherService: AppSwitcherControlling
    let appSwitcherController: AppSwitcherController
    let windowSnapHotKeyService: WindowSnapHotKeyControlling
    let titlebarGestureService: TitlebarGestureControlling
    private let findMouseCoordinator: FindMouseCoordinator
    private let defaultInputSourceCoordinator: DefaultInputSourceCoordinator
    private let panelHotKeyService: PanelHotKeyControlling
    static let windowMenuActions: [(tag: Int, action: WindowSnapAction)] = [
        (1, .leftHalf), (2, .rightHalf), (3, .topHalf), (4, .bottomHalf), (5, .topLeft), (6, .topRight),
        (7, .bottomLeft), (8, .bottomRight), (9, .leftThird), (10, .leftTwoThirds), (11, .centerThird),
        (12, .rightTwoThirds), (13, .rightThird), (14, .previousDisplay), (15, .nextDisplay),
        (16, .maximize), (17, .center), (18, .restore), (19, .minimize)
    ]

    override init() {
        self.settings = SettingsManager.shared
        self.monitor = SystemMonitor.shared
        self.displayControlManager = DisplayControlManager.shared
        self.appMemoryManager = AppMemoryManager.shared
        self.scrollService = ScrollDirectionService()
        let windowSnappingService = WindowSnappingService()
        self.windowSnappingService = windowSnappingService
        let windowSnapPreview = WindowSnapPreviewService()
        self.windowSnapPreview = windowSnapPreview
        self.windowSnapHotKeyService = WindowSnapHotKeyService(snappingService: windowSnappingService)
        self.titlebarGestureService = TitlebarGestureService(
            snappingService: windowSnappingService,
            previewService: windowSnapPreview
        )
        self.windowDragMonitorService = WindowDragMonitorService()
        self.snapIslandController = SnapIslandController()
        let windowThumbnailService = WindowThumbnailService()
        self.windowThumbnailService = windowThumbnailService
        self.windowPreviewIndex = WindowPreviewIndex.shared
        self.dockHoverMonitor = DockHoverMonitorService()
        self.dockPreviewController = DockPreviewController()
        self.appSwitcherService = AppSwitcherService()
        self.appSwitcherController = AppSwitcherController()
        let findMouseService = FindMouseService(presentationPointer: PresentationPointerService())
        self.findMouseCoordinator = FindMouseCoordinator(settings: settings, service: findMouseService)
        self.defaultInputSourceCoordinator = DefaultInputSourceCoordinator.shared
        let panelHotKeyService = PanelHotKeyService()
        self.panelHotKeyService = panelHotKeyService
        super.init()
        panelHotKeyService.onPressed = { [weak self] in
            self?.presentCleanupPanelAtPointer()
        }
        configureWindowSnapPipeline()
        configureWindowPreviewPipeline()
        ApplicationActivationTracker.shared.seed(from: NSWorkspace.shared.runningApplications)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        recordApplicationLaunch()
        DiagnosticReportService.recordEnvironmentBaseline()
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

        observePreferenceChanges()

        // 启动时按当前设置同步一次（推送配置 + 决定是否启动 tap）。
        syncScrollService()
        syncWindowControlServices()
        findMouseCoordinator.start()
        defaultInputSourceCoordinator.start()
        syncPanelHotKeyService()
        syncFinderMenuService()
        syncKeepAwakeService()
        displayControlManager.setEnabled(settings.displayBrightnessControlEnabled)
        // 启动即发布一次本地化标题，确保扩展冷启动就能读到当前语言的菜单文案。
        FinderMenuHostService.shared.publishLabels()

        // 回到前台时复查权限：用户可能刚授权，开关开着但 tap 尚未建起来。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApplicationPID = frontmost.processIdentifier
        }
        // A display change moves every visible frame, so the cached screen snapshot must not
        // outlive it — snapping on the wrong display's geometry is exactly the multi-monitor bug
        // the flip reference exists to prevent.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
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

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        // Calculate initial width based on enabled items
        let initialWidth = StatusBarView.calculateWidth(
            settings: settings,
            hasFanHardware: monitor.hasFanHardware,
            hasBatteryHardware: monitor.hasBatteryHardware
        )

        statusItem = NSStatusBar.system.statusItem(withLength: initialWidth)

        if let button = statusItem?.button {
            // Create custom status bar view
            let view = StatusBarView(frame: NSRect(x: 0, y: 0, width: initialWidth, height: 22))
            statusBarView = view
            // Keep the transparent host in the button's hierarchy so the fan's Core Animation
            // layer shares the status-item window and continues to use the original button hit area.
            button.addSubview(view)
            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]
            button.imagePosition = .imageOnly
            view.attach(to: button)

            button.action = #selector(togglePanel)
            button.target = self
        }
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
                .environmentObject(displayControlManager)
        )

        // 失去 key 焦点（点击外部 / 切换到别的菜单栏图标）时自动关闭，
        // 复刻 NSPopover .transient 行为，无需再次点击图标手动隐藏。
        panel.onResignKey = { [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.dismissPanel(reason: .resignKey)
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
            Publishers.CombineLatest(
                Publishers.CombineLatest3(
                    monitor.$networkUpload,
                    monitor.$networkDownload,
                    monitor.$fanSpeed
                ),
                Publishers.CombineLatest(
                    monitor.$hasFanHardware,
                    monitor.$hasBatteryHardware
                )
            )
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] values in
            let (main, networkAndHardware) = values
            let (cpu, gpu, memory, disk) = main
            let (network, _) = networkAndHardware
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
            metrics: StatusBarView.Metrics(
                cpu: cpu,
                gpu: gpu,
                memory: memory,
                disk: disk,
                upload: upload,
                download: download,
                fan: fan,
                battery: monitor.battery,
                health: monitor.health,
                hasFanHardware: monitor.hasFanHardware,
                hasBatteryHardware: monitor.hasBatteryHardware
            ),
            settings: settings
        )

        // Update status item width
        let newWidth = StatusBarView.calculateWidth(
            settings: settings,
            hasFanHardware: monitor.hasFanHardware,
            hasBatteryHardware: monitor.hasBatteryHardware
        )
        statusItem?.length = newWidth
        statusBarView?.frame.size.width = newWidth
    }

    // MARK: - Actions

    /// 统一关闭面板：隐藏、同步状态、停止采集、移除外部点击监听。
    private func dismissPanel(reason: PanelDismissReason) {
        guard panel?.isVisible == true else { return }
        recordPanelClosed(reason: reason)
        panel?.orderOut(nil)
        if reason.isAutomatic { panelAutoClosedAt = Date() }
        monitor.setPopoverVisible(false)
        displayControlManager.setPanelVisible(false)
        appMemoryManager.stopMonitoring()
        removeOutsideClickMonitors()
    }

    /// 点面板外任何地方关掉：其他 App（全局监听 / 本 App 失活）和本进程其它窗口（本地监听）。
    /// 监控状态项的点击留给 `togglePanel`，不在这里关。
    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            self.lastGlobalMouseDownAt = Date()
            self.dismissPanel(reason: .globalMouseDown)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleLocalMouseDown(event)
            return event
        }
    }

    private func handleLocalMouseDown(_ event: NSEvent) {
        guard let panel, panel.isVisible else { return }
        if event.window === panel { return }
        if event.window === statusItem?.button?.window { return }
        lastGlobalMouseDownAt = Date()
        dismissPanel(reason: .localMouseDown)
    }

    private func removeOutsideClickMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
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
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // Stable identity for the close-classification evidence (`PanelKeyWindowRole`).
        window.identifier = NSUserInterfaceItemIdentifier(PanelKeyWindowRole.aboutIdentifier)
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
            if panelAnchor != .pointer {
                dismissPanel(reason: .statusItemToggle)
                return
            }
            // 指针处已打开：点菜单栏把面板移回图标下方，而不是关掉。
        } else if let closedAt = panelAutoClosedAt,
                  Date().timeIntervalSince(closedAt) < 0.25,
                  panelAnchor != .pointer {
            // 图标下方的面板因点图标先 resignKey 再进这里，视为关闭，不要立刻重开。
            panelAutoClosedAt = nil
            return
        }

        panelAutoClosedAt = nil
        guard let buttonWindow = button.window else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)

        let panelSize = panel.frame.size
        let panelOrigin = NSPoint(
            x: buttonRectOnScreen.midX - (panelSize.width / 2),
            y: buttonRectOnScreen.minY - panelSize.height - 6
        )
        showPanel(at: panelOrigin, source: "statusItem")
    }

    /// 全局热键：在指针处打开清理页。已打开则关闭。
    func presentCleanupPanelAtPointer() {
        guard let panel else { return }
        if panel.isVisible {
            dismissPanel(reason: .hotkeyToggle)
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(origin: mouse, size: panel.frame.size)
        let origin = PanelPointerPlacement.origin(
            size: panel.frame.size,
            mouse: mouse,
            visibleFrame: visibleFrame
        )
        NotificationCenter.default.post(
            name: .popoverSelectTab,
            object: nil,
            userInfo: ["tab": 1]
        )
        showPanel(at: origin, source: "hotkey")
    }

    private func showPanel(at origin: NSPoint, source: String) {
        guard let panel else { return }
        panel.setFrameOrigin(origin)
        var fields = panelDiagnosticFields()
        fields["source"] = source
        DiagnosticLogService.record(
            category: "popover",
            action: "opened",
            fields: fields
        )
        panelAnchor = source == "hotkey" ? .pointer : .statusItem
        AIUsageMonitor.shared.refreshIfStale()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor.setPopoverVisible(true)
        displayControlManager.setPanelVisible(true)
        // 面板一打开即预热进程内存扫描，用户从 Overview 切到 Cleanup 时数据已就绪。
        // Cleanup 页的 onAppear/onDisappear 仍会幂等地接管 start/stop。
        appMemoryManager.startMonitoring()
        installOutsideClickMonitors()
    }

    // MARK: - Scroll Direction

    /// 尝试启动滚动方向翻转服务。若 tap 创建失败（缺少 Accessibility 权限），
    /// 弹出权限引导对话框；保持开关开启，待用户授权后前台激活时自动重试。
    private func startScrollServiceOrPrompt() {
        guard !scrollService.isRunning else { return }
        if scrollService.start() { return }

        // 权限不足：先不带弹窗检测一次状态
        guard scrollService.checkPermission(promptIfNeeded: false) else {
            presentScrollPermissionAlert()
            return
        }
        // 权限已满足但 tap 创建仍失败（罕见：其他系统问题）→ 静默，开关保持 on
    }

    @objc private func handleAppDidResignActive() {
        guard panel?.isVisible == true else { return }
        dismissPanel(reason: .resignActive)
    }

    @objc private func handleAppDidBecomeActive() {
        if currentScrollConfig().isActive, !scrollService.isRunning {
            scrollService.updateConfig(currentScrollConfig())
            _ = scrollService.start()
        }
        findMouseCoordinator.retryIfNeeded()
        refreshWindowThumbnailAuthorization()
        syncPanelHotKeyService()
        syncWindowControlServices()
        displayControlManager.applicationDidBecomeActive()
        if settings.finderMenuEnabled {
            syncFinderMenuService()
            FinderMenuConfigStore.shared.refreshExtensionStatus()
        }
    }

    private func currentScrollConfig() -> ScrollConfig {
        ScrollConfig(
            reverseVertical: settings.scrollReverseEnabled,
            reverseHorizontal: settings.scrollReverseHorizontalEnabled,
            stepMultiplier: settings.scrollStepMultiplier,
            disableAcceleration: settings.scrollDisableAcceleration,
            scrollLines: settings.scrollLines,
            includeTrackpad: settings.scrollIncludeTrackpad
        )
    }

    /// 窗口管理总开关统一驱动：开 → 图标 + 快捷键 + 手势全起；关 → 三者一起停。
    private func syncWindowControlServices() {
        if settings.windowManagementEnabled {
            ensureWindowControlsStatusItem()
            startWindowSnapHotKeysOrPrompt()
            startTitlebarGesturesOrPrompt()
        } else {
            windowSnapHotKeyService.stop()
            titlebarGestureService.stop()
            removeWindowControlsStatusItem()
        }
        syncWindowSnapPipeline()
        syncWindowPreviewPipeline(settings.windowSnap)
    }

    private func startWindowSnapHotKeysOrPrompt() {
        if windowSnapHotKeyService.start(shortcuts: settings.windowSnap.shortcuts) { return }
        // Nothing bound is a legitimate configuration, not a failure — only prompt when a binding
        // exists that could not be registered, which is the permission case.
        guard settings.windowSnap.shortcuts.contains(where: \.isBound) else { return }
        if !windowSnappingService.checkPermission(promptIfNeeded: false) {
            presentWindowControlPermissionAlert()
        }
    }

    private func startTitlebarGesturesOrPrompt() {
        guard !titlebarGestureService.isRunning else { return }
        if titlebarGestureService.start() { return }
        presentWindowControlPermissionAlert()
    }

    /// 同步滚动服务：热更新配置；按「垂直∨水平反转∨关闭加速度」决定 tap 起停。步长倍率
    /// 与触控板开关依附于这些主开关 —— 仅在 tap 运行时生效，单独调整不会启动 tap。
    private func syncScrollService() {
        let config = currentScrollConfig()
        scrollService.updateConfig(config)
        if config.isActive {
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

    func presentWindowControlPermissionAlert() {
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
        dismissPanel(reason: .externalRequest)
    }

    private func syncKeepAwakeService() {
        if settings.keepAwakeEnabled {
            KeepAwakeService.shared.start()
        } else {
            KeepAwakeService.shared.stop()
        }
    }

    private func syncPanelHotKeyService(announceFailure: Bool = false) {
        if settings.cleanupPanelHotKeyEnabled {
            if panelHotKeyService.start(hotKey: settings.cleanupPanelHotKey) { return }
            guard announceFailure else { return }
            ToastCenter.shared.show(
                message: "settings.cleanupHotKey.registerFailed".localized,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                duration: 3
            )
        } else {
            panelHotKeyService.stop()
        }
    }

    private func syncFinderMenuService() {
        FinderMenuShared.setEnabled(settings.finderMenuEnabled)
        if settings.finderMenuEnabled {
            FinderMenuHostService.shared.publishLabels()
            FinderMenuHostService.shared.start()
        } else {
            FinderMenuHostService.shared.stop()
        }
    }

    func stopRuntimeServices() {
        statusBarView?.stopFanAnimation()
        monitor.stopMonitoring()
        appMemoryManager.stopMonitoring()
        displayControlManager.stop()
        AIUsageMonitor.shared.stop()
        UsageWarmupManager.shared.stopAll()
        scrollService.stop()
        windowSnapHotKeyService.stop()
        titlebarGestureService.stop()
        windowDragMonitorService.stop()
        snapIslandController.dismissImmediately()
        windowSnapPreview.dismissImmediately()
        dockHoverMonitor.stop()
        dockPreviewController.dismissImmediately()
        appSwitcherService.stop()
        appSwitcherController.dismissImmediately()
        findMouseCoordinator.stop()
        panelHotKeyService.stop()
        defaultInputSourceCoordinator.stop()
        FinderMenuHostService.shared.stop()
        KeepAwakeService.shared.stop()
        SMCInfo.shutdown()
    }
}

private extension AppDelegate {
    func observePreferenceChanges() {
        // 滚动处理：垂直反转 / 水平反转 / 步长倍率 / 加速度 / 触控板 任一变更都重新同步服务。
        Publishers.MergeMany([
            settings.$scrollReverseEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$scrollReverseHorizontalEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$scrollStepMultiplier.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$scrollDisableAcceleration.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$scrollLines.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$scrollIncludeTrackpad.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncScrollService() }
            .store(in: &cancellables)

        // 窗口管理总开关：单一开关同时驱动菜单栏图标、快捷键、标题栏手势的起停。
        settings.$windowManagementEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.windowControlPermissionAlertShown = false
                self?.syncWindowControlServices()
            }
            .store(in: &cancellables)

        // 窗口管理子配置：间距、触发区、悬浮岛、排除列表、快捷键。任一变更都重新下发。
        settings.$windowSnap
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] configuration in
                self?.applyWindowSnapConfiguration(configuration)
            }
            .store(in: &cancellables)

        // Finder 右键菜单总开关：开 → 注册宿主 CFMessagePort；关 → 注销。
        settings.$finderMenuEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncFinderMenuService() }
            .store(in: &cancellables)

        // 保持唤醒总开关：开 → 空闲断言 + 插电合盖虚拟屏；关 → 全部释放。
        settings.$keepAwakeEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncKeepAwakeService() }
            .store(in: &cancellables)

        settings.$displayBrightnessControlEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.displayControlManager.setEnabled(enabled)
            }
            .store(in: &cancellables)

        Publishers.Merge(
            settings.$cleanupPanelHotKeyEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$cleanupPanelHotKey.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.syncPanelHotKeyService(announceFailure: true) }
        .store(in: &cancellables)

        // Finder 菜单本地化标题：语言变更时重新发布到 App Group 供扩展读取。
        settings.$appLanguage
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { _ in FinderMenuHostService.shared.publishLabels() }
            .store(in: &cancellables)
    }
}
