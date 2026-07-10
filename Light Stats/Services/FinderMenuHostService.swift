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

    private let logger = Logger(subsystem: "com.lightstats.findermenu", category: "Host")
    private var localPort: CFMessagePort?
    private var runLoopSource: CFRunLoopSource?

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

        // 检查扩展侧是否有挂起的 IPC 失败（宿主之前不在运行），有就 toast。
        if let failedAction = FinderMenuShared.consumePendingFailure() {
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
        FinderMenuShared.setLabels(labels)
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

    private func handle(_ request: FinderMenuRequest) {
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
        case .cmuxNewWindow:
            performCmuxService("New cmux Window Here", request: request)
        case .cmuxNewWorkspace:
            performCmuxService("New cmux Workspace Here", request: request)
        case .copyPath, .copyName:
            // 这些动作在扩展内已处理，不应抵达宿主；忽略。
            break
        }
    }

    // MARK: - Open Terminal

    /// 在目标目录打开用户选择的终端。默认 Terminal，不根据安装情况替用户猜。
    private func openTerminal(_ request: FinderMenuRequest) {
        guard let dir = directory(for: request) else {
            showFailure("findermenu.toast.noTarget")
            return
        }
        let terminalID = FinderMenuShared.loadConfig().terminalID
        if !openTerminal(id: terminalID, at: URL(fileURLWithPath: dir, isDirectory: true)) {
            showFailure("findermenu.toast.openTerminalFailed")
        }
    }

    private func openTerminal(id: String, at directory: URL) -> Bool {
        switch FinderMenuPresets.normalizeTerminalID(id) {
        case "iterm2":
            return openApplication(bundleIdentifier: "com.googlecode.iterm2", urls: [directory])
                || runProcess("/usr/bin/open", arguments: ["-a", "iTerm", directory.path]) == 0
                || openTerminalApp(at: directory)
        case "ghostty":
            return openTerminalWithArguments(
                bundleIdentifier: "com.mitchellh.ghostty",
                appName: "Ghostty",
                arguments: ["--working-directory=\(directory.path)"]
            ) || openTerminalApp(at: directory)
        case "wezterm":
            return openTerminalWithArguments(
                bundleIdentifier: "com.github.wez.wezterm",
                appName: "WezTerm",
                arguments: ["start", "--cwd", directory.path]
            ) || openTerminalApp(at: directory)
        case "alacritty":
            return openTerminalWithArguments(
                bundleIdentifier: "org.alacritty",
                appName: "Alacritty",
                arguments: ["--working-directory", directory.path]
            ) || openTerminalApp(at: directory)
        case "kitty":
            return openTerminalWithArguments(
                bundleIdentifier: "net.kovidgoyal.kitty",
                appName: "kitty",
                arguments: ["--directory", directory.path]
            ) || openTerminalApp(at: directory)
        case "warp":
            return runProcess("/usr/bin/open", arguments: ["-a", "Warp", directory.path]) == 0 || openTerminalApp(at: directory)
        case "cmux":
            return openApplication(bundleIdentifier: "com.cmuxterm.app", urls: [directory])
        default:
            return openTerminalApp(at: directory)
        }
    }

    private func openTerminalApp(at directory: URL) -> Bool {
        if openApplication(bundleIdentifier: "com.apple.Terminal", urls: [directory]) {
            return true
        }
        if runProcess("/usr/bin/open", arguments: ["-a", "Terminal", directory.path]) == 0 {
            return true
        }
        let command = "cd \(shellQuoted(directory.path))"
        let script = """
        tell application "Terminal"
          activate
          do script "\(appleScriptEscaped(command))"
        end tell
        """
        return runProcess("/usr/bin/osascript", arguments: ["-e", script]) == 0
    }

    private func openTerminalWithArguments(bundleIdentifier: String, appName: String, arguments: [String]) -> Bool {
        var bundleArguments = ["-n", "-b", bundleIdentifier, "--args"]
        bundleArguments.append(contentsOf: arguments)
        if runProcess("/usr/bin/open", arguments: bundleArguments) == 0 {
            return true
        }
        var appArguments = ["-n", "-a", appName, "--args"]
        appArguments.append(contentsOf: arguments)
        return runProcess("/usr/bin/open", arguments: appArguments) == 0
    }

    // MARK: - New File

    /// 在容器目录按模板新建文件，自增重名后写入内容并在 Finder 中选中。
    /// 模板取用户配置（resolvedTemplates 在无自定义时回退预设），与扩展菜单一致。
    private func newFile(_ request: FinderMenuRequest) {
        guard let dir = directory(for: request), let id = request.parameter else {
            showFailure("findermenu.toast.noTarget")
            return
        }
        guard let template = FinderMenuShared.loadConfig().resolvedTemplates().first(where: { $0.id == id }) else {
            showFailure("findermenu.toast.newFileFailed")
            return
        }

        let dest = uniqueURL(inDirectory: dir, baseName: "Untitled", fileExtension: template.fileExtension)
        do {
            try template.content.write(to: dest, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            logger.error("newFile failed: \(error.localizedDescription, privacy: .public)")
            showFailure("findermenu.toast.newFileFailed")
        }
    }

    // MARK: - Move / Copy

    /// 把选中项移动或复制到目标目录，逐个处理并对重名自增。
    private func transfer(_ request: FinderMenuRequest, move: Bool) {
        guard let dest = request.parameter, !request.paths.isEmpty else {
            showFailure("findermenu.toast.noTarget")
            return
        }
        let fileManager = FileManager.default
        var failureCount = 0
        for path in request.paths {
            let source = URL(fileURLWithPath: path)
            let name = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            let target = uniqueURL(inDirectory: dest, baseName: name, fileExtension: ext)
            do {
                if move {
                    try fileManager.moveItem(at: source, to: target)
                } else {
                    try fileManager.copyItem(at: source, to: target)
                }
            } catch {
                failureCount += 1
                logger.error("\(move ? "move" : "copy", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if failureCount > 0 {
            showFailure(move ? "findermenu.toast.moveFailed" : "findermenu.toast.copyFailed")
        }
    }

    // MARK: - Open With App

    /// 用指定 bundle id 的 App 打开选中项；无选中项时打开容器目录。
    private func openWithApp(_ request: FinderMenuRequest) {
        guard let bundleID = request.parameter else {
            showFailure("findermenu.toast.openWithFailed")
            return
        }
        let targets = request.paths.isEmpty ? [request.container].compactMap { $0 } : request.paths
        guard !targets.isEmpty, runProcess("/usr/bin/open", arguments: ["-b", bundleID] + targets) == 0 else {
            showFailure("findermenu.toast.openWithFailed")
            return
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
                logger.error("toggleHidden failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if failureCount > 0 {
            showFailure("findermenu.toast.toggleHiddenFailed")
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
    }

    // MARK: - Helpers

    private func directory(for request: FinderMenuRequest) -> String? {
        if let container = request.container {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: container, isDirectory: &isDir), isDir.boolValue {
                return container
            }
            // container 不是目录（Finder 在某些上下文中可能返回文件路径），取父目录。
            return (container as NSString).deletingLastPathComponent
        }
        guard let first = request.paths.first else { return nil }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: first, isDirectory: &isDir)
        return isDir.boolValue ? first : (first as NSString).deletingLastPathComponent
    }

    /// 在目录内生成不与现有文件冲突的 URL：`base.ext` → `base 2.ext` → `base 3.ext`。
    private func uniqueURL(inDirectory dir: String, baseName: String, fileExtension: String) -> URL {
        let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
        let fileManager = FileManager.default
        func make(_ name: String) -> URL {
            fileExtension.isEmpty
                ? dirURL.appendingPathComponent(name)
                : dirURL.appendingPathComponent(name).appendingPathExtension(fileExtension)
        }
        var candidate = make(baseName)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = make("\(baseName) \(index)")
            index += 1
        }
        return candidate
    }

    private func openApplication(bundleIdentifier: String, urls: [URL]) -> Bool {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            logger.error("application not found: \(bundleIdentifier, privacy: .public)")
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if let error {
                self.logger.error("open app failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return true
    }

    @discardableResult
    private func runProcess(_ launchPath: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            let status = process.terminationStatus
            if status != 0 {
                logger.error("process failed: \(launchPath, privacy: .public) status=\(status)")
            }
            return status
        } catch {
            logger.error("process failed: \(error.localizedDescription, privacy: .public)")
            return -1
        }
    }

    private func showFailure(_ localizedKey: String) {
        NotificationCenter.default.post(
            name: .finderMenuActionFailed,
            object: nil,
            userInfo: ["message": localizedKey.localized]
        )
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func shellQuoted(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/-_.:")
        if value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

extension Notification.Name {
    static let finderMenuActionFailed = Notification.Name("finderMenuActionFailed")
}
