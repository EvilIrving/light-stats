//
//  FinderMenuHostService.swift
//  Light Stats
//
//  Finder 右键菜单宿主侧服务（Shape C，opt-in 生命周期）：注册 CFMessagePort 本地端口，
//  接收 FinderSync 扩展委派的动作，并以宿主（非沙盒）身份执行真正的文件 / 系统操作，
//  绕开扩展沙盒的文件写入限制。
//
//  总开关关闭时 stop()：端口注销，扩展即便发请求也连不上；且扩展自身也会因
//  FinderMenuShared.isEnabled() == false 而不出菜单。两道门都默认关，符合零侵扰契约。
//

import AppKit
import CoreFoundation
import Foundation
import os

@MainActor
final class FinderMenuHostService {

    static let shared = FinderMenuHostService()

    private let logger = AppLogger(category: "FinderMenuHost")
    private var localPort: CFMessagePort?
    private var runLoopSource: CFRunLoopSource?
    private var activeAction: FinderMenuAction?
    private var destinationPanel: NSOpenPanel?
    private var visibilityHostWindow: NSWindow?
    private var recentRequestIDs: [UUID] = []
    private var deliveryObserver: NSObjectProtocol?

    private(set) var isRunning = false

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }

        // CFMessagePort 回调是 C 函数指针，不能捕获 self。回调里只做 nonisolated 的解码，
        // 再把请求派回 MainActor 执行真正的动作。源挂在主 RunLoop，回调即在主线程触发。
        let callback: CFMessagePortCallBack = { _, _, data, _ in
            if let data = data as Data?, let request = FinderMenuRequest.decode(data) {
                Task { @MainActor in
                    FinderMenuHostService.shared.handle(request)
                }
            }
            return nil
        }

        guard let port = CFMessagePortCreateLocal(
            nil, FinderMenuShared.messagePortName as CFString, callback, nil, nil
        ) else {
            logger.error("Failed to create local message port")
            return
        }
        guard let source = CFMessagePortCreateRunLoopSource(nil, port, 0) else {
            logger.error("Failed to create run loop source for message port")
            CFMessagePortInvalidate(port)
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        localPort = port
        runLoopSource = source
        isRunning = true
        logger.info("FinderMenu host service started")

        deliveryObserver = DistributedNotificationCenter.default().addObserver(
            forName: FinderMenuShared.deliveryFailed, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.reportPendingFailure() }
        }
        reportPendingFailure()
    }

    private func reportPendingFailure() {
        // Failure can arrive after startup; listen as well as checking once at start.
        if let failedAction = FinderMenuShared.consumePendingFailure() {
            DiagnosticLogService.record(
                level: .error,
                category: "finderMenu.extension",
                action: "deliveryFailed",
                fields: ["finderAction": failedAction]
            )
            let label = FinderMenuShared.label(for: failedAction) ?? failedAction
            let message = String(format: "findermenu.toast.delayedFailure".localized, label)
            NotificationCenter.default.post(
                name: .finderMenuActionFailed,
                object: nil,
                userInfo: ["message": message]
            )
        }
    }

    func stop() {
        guard isRunning else { return }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let localPort {
            CFMessagePortInvalidate(localPort)
        }
        runLoopSource = nil
        localPort = nil
        destinationPanel?.cancel(nil)
        if let deliveryObserver { DistributedNotificationCenter.default().removeObserver(deliveryObserver) }
        deliveryObserver = nil
        destinationPanel = nil
        if let window = visibilityHostWindow, let sheet = window.attachedSheet {
            window.endSheet(sheet, returnCode: .abort)
        }
        visibilityHostWindow?.close()
        visibilityHostWindow = nil
        isRunning = false
        logger.info("FinderMenu host service stopped")
    }

    // MARK: - Localized labels

    /// 用宿主当前语言计算各动作的本地化菜单标题，写入 App Group 供扩展读取。
    /// 启动时与语言变更时调用——扩展进程无法用 `.localized`，只能读宿主发布的结果。
    func publishLabels() {
        var labels: [String: String] = [:]
        for action in FinderMenuAction.allCases {
            labels[action.rawValue] = "findermenu.menu.\(action.rawValue)".localized
        }
        for template in FinderMenuPresets.fileTemplates {
            let key = "findermenu.template.\(template.id)"
            let title = key.localized
            labels["template.\(template.id)"] = title == key ? template.title : title
        }
        labels["otherLocation"] = "findermenu.menu.otherLocation".localized
        FinderMenuShared.setLabels(labels)
        FinderMenuShared.setShowsHiddenFiles(FinderMenuSystemService.showsHiddenFiles)
    }

    // MARK: - Extension status

    /// 查询 FinderSync 扩展在系统 pkd 里的注册 / 启用状态。宿主非沙盒，可直接调 pluginkit。
    /// `nonisolated`：仅起子进程读管道，无 actor 状态——交给调用方在后台线程跑，避免阻塞主线程。
    /// pluginkit 输出首个非空行的首字符即状态标记：`+` 已启用，`-`/`?` 已注册未勾选，空 → 未注册。
    nonisolated static func extensionStatus() -> FinderExtensionStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-i", FinderMenuShared.extensionBundleID]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .unknown
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
            return .notRegistered
        }
        switch output.first {
        case "+": return .enabled
        case "-", "?": return .disabled
        default: return .unknown
        }
    }

    // MARK: - Action handling

    private func accept(_ request: FinderMenuRequest) -> Bool {
        guard isRunning, FinderMenuShared.isEnabled() else { return false }
        let config = FinderMenuShared.loadConfig()
        guard config.isActionEnabled(request.action) else { return false }
        if request.action == .cmuxNewWindow || request.action == .cmuxNewWorkspace {
            guard config.showCmuxActions else { return false }
        }
        if let id = request.requestID {
            guard !recentRequestIDs.contains(id) else { return false }
            recentRequestIDs.append(id)
            if recentRequestIDs.count > 128 { recentRequestIDs.removeFirst() }
        }
        return true
    }

    private func handle(_ request: FinderMenuRequest) {
        guard accept(request) else { return }
        activeAction = request.action
        defer { activeAction = nil }
        DiagnosticLogService.record(
            category: "finderMenu",
            action: "requested",
            fields: ["action": request.action.rawValue]
        )
        switch request.action {
        case .openTerminalHere:
            openTerminal(request)
        case .newFile:
            newFile(request)
        case .moveTo:
            transfer(request, move: true)
        case .copyTo:
            transfer(request, move: false)
        case .openWithApp:
            openWithApp(request)
        case .toggleHidden:
            toggleHidden(request)
        case .openDirectory:
            openDirectory(request)
        case .toggleHiddenFiles:
            toggleFinderVisibility()
        case .cmuxNewWindow:
            performCmuxService("New cmux Window Here", request: request)
        case .cmuxNewWorkspace:
            performCmuxService("New cmux Workspace Here", request: request)
        case .copyPath, .copyName:
            copyToPasteboard(request)
        }
    }

    private func copyToPasteboard(_ request: FinderMenuRequest) {
        let text = FinderMenuFileService.pasteboardText(for: request)
        guard !text.isEmpty else { return showFailure("findermenu.toast.noTarget") }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            return showFailure("findermenu.toast.copyFailed")
        }
        recordSuccess()
    }

    // MARK: - Open Terminal

    /// 在目标目录打开用户选择的终端。默认 Terminal，不根据安装情况替用户猜。
    private func openTerminal(_ request: FinderMenuRequest) {
        guard let directory = FinderMenuFileService.directory(for: request) else {
            return showFailure("findermenu.toast.noTarget")
        }
        let terminalID = FinderMenuShared.loadConfig().terminalID
        Task {
            if await FinderMenuTerminalService.open(id: terminalID, at: directory) {
                recordSuccess(action: request.action)
            } else {
                showFailure("findermenu.toast.openTerminalFailed", action: request.action)
            }
        }
    }

    // MARK: - New File

    /// 在容器目录按模板新建文件，自增重名后写入内容并在 Finder 中选中。
    /// 模板取用户配置（resolvedTemplates 在无自定义时回退预设），与扩展菜单一致。
    private func newFile(_ request: FinderMenuRequest) {
        guard let directory = FinderMenuFileService.directory(for: request), let id = request.parameter else {
            return showFailure("findermenu.toast.noTarget")
        }
        guard let template = FinderMenuShared.loadConfig().resolvedTemplates().first(where: { $0.id == id }) else {
            return showFailure("findermenu.toast.newFileFailed")
        }
        Task {
            do {
                let destination = try await FinderMenuFileService.shared.createFile(from: template, in: directory)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
                recordSuccess(action: request.action)
            } catch {
                showFailure("findermenu.toast.newFileFailed", action: request.action)
            }
        }
    }

    // MARK: - Move / Copy

    private func transfer(_ request: FinderMenuRequest, move: Bool) {
        guard !request.paths.isEmpty else { return showFailure("findermenu.toast.noTarget") }
        guard let path = request.parameter else {
            chooseDestination(for: request, move: move)
            return
        }
        let destination = URL(fileURLWithPath: path, isDirectory: true)
        Task {
            do {
                let result = try await FinderMenuFileService.shared.transfer(paths: request.paths, to: destination, move: move)
                if result.failed > 0 {
                    let message = String(format: "findermenu.toast.transferPartial".localized, result.completed, result.failed)
                    showFailure(move ? "findermenu.toast.moveFailed" : "findermenu.toast.copyFailed",
                                action: request.action, message: message)
                } else {
                    recordSuccess(action: request.action)
                }
            } catch {
                showFailure(move ? "findermenu.toast.moveFailed" : "findermenu.toast.copyFailed", action: request.action)
            }
        }
    }

    private func chooseDestination(for request: FinderMenuRequest, move: Bool) {
        guard destinationPanel == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = (move ? "findermenu.choose.move" : "findermenu.choose.copy").localized
        panel.message = "findermenu.choose.destination".localized
        panel.directoryURL = FinderMenuFileService.directory(for: request)
        destinationPanel = panel
        NotificationCenter.default.post(name: .finderMenuFilePanelWillPresent, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            NotificationCenter.default.post(name: .finderMenuFilePanelDidDismiss, object: nil)
            guard let self else { return }
            self.destinationPanel = nil
            guard response == .OK, let destination = panel.url,
                  self.isRunning, FinderMenuShared.isEnabled() else { return }
            let resolved = FinderMenuRequest(action: request.action, paths: request.paths,
                                             container: request.container, parameter: destination.path)
            self.transfer(resolved, move: move)
        }
    }

    private func openDirectory(_ request: FinderMenuRequest) {
        guard let path = request.parameter,
              (try? URL(fileURLWithPath: path).resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true)) else {
            return showFailure("findermenu.toast.openDirectoryFailed")
        }
        recordSuccess()
    }

    private func toggleFinderVisibility() {
        guard visibilityHostWindow == nil else { return }
        let show = !FinderMenuSystemService.showsHiddenFiles
        let alert = NSAlert()
        alert.messageText = (show ? "findermenu.visibility.show" : "findermenu.visibility.hide").localized
        alert.informativeText = "findermenu.visibility.restartHint".localized
        alert.addButton(withTitle: "findermenu.visibility.apply".localized)
        alert.addButton(withTitle: "findermenu.visibility.cancel".localized)
        NSApp.activate(ignoringOtherApps: true)
        let window = visibilityWindow()
        visibilityHostWindow = window
        alert.beginSheetModal(for: window) { [weak self] response in
            window.close()
            self?.visibilityHostWindow = nil
            guard response == .alertFirstButtonReturn, let self,
                  self.isRunning, FinderMenuShared.isEnabled() else { return }
            Task {
                guard FinderMenuSystemService.setShowsHiddenFiles(show), await FinderMenuSystemService.restartFinder() else {
                    self.showFailure("findermenu.toast.visibilityFailed", action: .toggleHiddenFiles)
                    return
                }
                self.recordSuccess(action: .toggleHiddenFiles)
            }
        }
    }

    private func visibilityWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 1),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        return window
    }

    // MARK: - Open With App

    /// 用指定 bundle id 的 App 打开选中项；无选中项时打开容器目录。
    private func openWithApp(_ request: FinderMenuRequest) {
        guard let bundleID = request.parameter else {
            showFailure("findermenu.toast.openWithFailed")
            return
        }
        let targets = request.paths.isEmpty ? [request.container].compactMap { $0 } : request.paths
        guard !targets.isEmpty else { return showFailure("findermenu.toast.noTarget") }
        Task {
            let opened = await FinderMenuTerminalService.openApplication(
                bundleID: bundleID, urls: targets.map { URL(fileURLWithPath: $0) }
            )
            if opened {
                recordSuccess(action: request.action)
            } else {
                showFailure("findermenu.toast.openWithFailed", action: request.action)
            }
        }
    }

    // MARK: - Hide / Show

    /// 切换选中项的隐藏标志。逐项读取当前状态再反转。
    private func toggleHidden(_ request: FinderMenuRequest) {
        guard !request.paths.isEmpty else {
            showFailure("findermenu.toast.noTarget")
            return
        }
        var failureCount = 0
        for path in request.paths {
            let url = URL(fileURLWithPath: path)
            do {
                let current = try url.resourceValues(forKeys: [.isHiddenKey]).isHidden ?? false
                var values = URLResourceValues()
                values.isHidden = !current
                var mutableURL = url
                try mutableURL.setResourceValues(values)
            } catch {
                failureCount += 1
                logger.error("toggleHidden failed: \(error.localizedDescription)")
            }
        }
        if failureCount > 0 {
            showFailure("findermenu.toast.toggleHiddenFailed")
        } else {
            recordSuccess()
        }
    }

    // MARK: - cmux Services

    private func performCmuxService(_ serviceName: String, request: FinderMenuRequest) {
        guard let dir = directory(for: request) else {
            showFailure("findermenu.toast.noTarget")
            return
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.lightstats.findermenu.cmux"))
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.path, forType: .string)
        guard NSPerformService(serviceName, pasteboard) else {
            showFailure("findermenu.toast.cmuxFailed")
            return
        }
        recordSuccess()
    }

    // MARK: - Helpers

    private func directory(for request: FinderMenuRequest) -> String? {
        FinderMenuFileService.directory(for: request)?.path
    }

    private func showFailure(_ localizedKey: String, action: FinderMenuAction? = nil, message: String? = nil) {
        DiagnosticLogService.record(
            level: .error,
            category: "finderMenu",
            action: "failed",
            fields: [
                "finderAction": (action ?? activeAction)?.rawValue ?? "unknown",
                "reason": localizedKey
            ]
        )
        NotificationCenter.default.post(
            name: .finderMenuActionFailed,
            object: nil,
            userInfo: ["message": message ?? localizedKey.localized]
        )
    }

    private func recordSuccess(action: FinderMenuAction? = nil) {
        DiagnosticLogService.record(
            category: "finderMenu",
            action: "succeeded",
            fields: ["finderAction": (action ?? activeAction)?.rawValue ?? "unknown"]
        )
    }

}

extension Notification.Name {
    static let finderMenuActionFailed = Notification.Name("finderMenuActionFailed")
    static let finderMenuFilePanelWillPresent = Notification.Name("finderMenuFilePanelWillPresent")
    static let finderMenuFilePanelDidDismiss = Notification.Name("finderMenuFilePanelDidDismiss")
}
