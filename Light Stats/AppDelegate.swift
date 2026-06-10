import AppKit
import SwiftUI
import Combine

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
        observePresetChanges()

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

    // MARK: - Preset Change Observation

    private func observePresetChanges() {
        settings.$appearancePreset
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] preset in
                self?.handlePresetChanged(preset)
            }
            .store(in: &cancellables)
    }

    private func handlePresetChanged(_ preset: AppearancePreset) {
        let layout = preset.layout
        let theme = preset.theme

        // Force dark appearance for terminal
        if theme.forceDarkAppearance {
            panel?.appearance = NSAppearance(named: .darkAqua)
        } else {
            panel?.appearance = nil
        }

        // Resize panel
        if let panel = panel {
            let newSize = layout.popoverSize
            var frame = panel.frame
            let oldSize = frame.size
            frame.origin.x += (oldSize.width - newSize.width) / 2
            frame.origin.y += (oldSize.height - newSize.height) / 2
            frame.size = newSize
            panel.setFrame(frame, display: true, animate: true)
        }

        // Rebuild status bar item with new width
        let newWidth = StatusBarView.calculateWidth(settings: settings)
        statusItem?.length = newWidth
        statusBarView?.frame.size.width = newWidth
        statusBarView?.needsDisplay = true
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        let initialWidth = StatusBarView.calculateWidth(settings: settings)

        statusItem = NSStatusBar.system.statusItem(withLength: initialWidth)

        if let button = statusItem?.button {
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
        let layout = settings.appearancePreset.layout
        let size = layout.popoverSize

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
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

        // Terminal theme forces dark appearance
        if settings.appearancePreset.theme.forceDarkAppearance {
            panel.appearance = NSAppearance(named: .darkAqua)
        }

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let contentView = PopoverContentView()
            .environmentObject(monitor)
            .environmentObject(AIUsageMonitor.shared)
            .environment(\.appTheme, settings.appearancePreset.theme)

        panel.contentViewController = NSHostingController(rootView: contentView)

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
        AIUsageMonitor.shared.start()

        settings.$refreshRate
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak monitor = self.monitor] newRate in
                monitor?.startMonitoring(interval: newRate.interval)
            }
            .store(in: &cancellables)

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

        let theme = settings.appearancePreset.theme
        if theme.forceDarkAppearance {
            window.appearance = NSAppearance(named: .darkAqua)
        }

        window.contentViewController = NSHostingController(
            rootView: AboutView()
                .environment(\.appTheme, theme)
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

        let preset = settings.appearancePreset

        // Force dark appearance for terminal
        if preset.theme.forceDarkAppearance {
            panel.appearance = NSAppearance(named: .darkAqua)
        } else {
            panel.appearance = nil
        }

        // Update content view with current theme before showing
        let contentView = PopoverContentView()
            .environmentObject(monitor)
            .environmentObject(AIUsageMonitor.shared)
            .environment(\.appTheme, preset.theme)
        panel.contentViewController = NSHostingController(rootView: contentView)

        // Ensure panel size matches current preset
        let layoutSize = preset.layout.popoverSize
        if panel.frame.size != layoutSize {
            var frame = panel.frame
            let oldSize = frame.size
            frame.origin.x += (oldSize.width - layoutSize.width) / 2
            frame.origin.y += (oldSize.height - layoutSize.height) / 2
            frame.size = layoutSize
            panel.setFrame(frame, display: false)
        }

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
