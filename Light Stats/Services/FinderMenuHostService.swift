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
        case .copyPath, .copyName:
            // 这些动作在扩展内已处理，不应抵达宿主；忽略。
            break
        }
    }

    // MARK: - Open Terminal

    /// 在目标目录打开终端。优先用容器路径；否则取首个选中项所在目录。
    private func openTerminal(_ request: FinderMenuRequest) {
        guard let dir = directory(for: request) else { return }
        runOpen(["-a", "Terminal", dir])
    }

    // MARK: - New File

    /// 在容器目录按模板新建文件，自增重名后写入内容并在 Finder 中选中。
    /// 模板取用户配置（resolvedTemplates 在无自定义时回退预设），与扩展菜单一致。
    private func newFile(_ request: FinderMenuRequest) {
        guard let dir = directory(for: request),
              let id = request.parameter,
              let template = FinderMenuShared.loadConfig().resolvedTemplates().first(where: { $0.id == id }) else { return }

        let base = "Untitled"
        let dest = uniqueURL(inDirectory: dir, baseName: base, fileExtension: template.fileExtension)
        do {
            try template.content.write(to: dest, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            logger.error("newFile failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Move / Copy

    /// 把选中项移动或复制到目标目录，逐个处理并对重名自增。
    private func transfer(_ request: FinderMenuRequest, move: Bool) {
        guard let dest = request.parameter else { return }
        let fileManager = FileManager.default
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
                logger.error("\(move ? "move" : "copy", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Open With App

    /// 用指定 bundle id 的 App 打开选中项；无选中项时打开容器目录。
    private func openWithApp(_ request: FinderMenuRequest) {
        guard let bundleID = request.parameter else { return }
        let targets = request.paths.isEmpty ? [request.container].compactMap { $0 } : request.paths
        guard !targets.isEmpty else { return }
        runOpen(["-b", bundleID] + targets)
    }

    // MARK: - Hide / Show

    /// 切换选中项的隐藏标志。逐项读取当前状态再反转。
    private func toggleHidden(_ request: FinderMenuRequest) {
        for path in request.paths {
            let url = URL(fileURLWithPath: path)
            do {
                let current = try url.resourceValues(forKeys: [.isHiddenKey]).isHidden ?? false
                var values = URLResourceValues()
                values.isHidden = !current
                var mutableURL = url
                try mutableURL.setResourceValues(values)
            } catch {
                logger.error("toggleHidden failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Helpers

    private func directory(for request: FinderMenuRequest) -> String? {
        if let container = request.container {
            return container
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

    /// 调用 `/usr/bin/open` 执行系统打开操作。
    private func runOpen(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            logger.error("open failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
