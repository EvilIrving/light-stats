//
//  FinderMenuIPCClient.swift
//  Light Stats / FinderMenuExtension
//
//  扩展侧 CFMessagePort 客户端：把需要文件操作的动作请求发给宿主注册的本地端口。
//  宿主未运行时先尝试拉起宿主、稍候端口注册后再重试一次。
//
//  `nonisolated`：从扩展 perform（MainActor）调用，但本身无隔离需求；CFMessagePort
//  的 remote 查找与发送是同步系统调用，超时短、不阻塞 UI。
//

import AppKit
import CoreFoundation
import Foundation
import os

nonisolated enum FinderMenuIPCClient {
    private static let messageID: Int32 = 1
    private static let sendTimeout: CFTimeInterval = 2.0

    static func send(_ request: FinderMenuRequest, logger: Logger) {
        guard let data = request.encoded() else { return }
        if trySend(data) { return }

        // 宿主可能没在运行：拉起后给它一点注册端口的时间再重试一次。
        launchHost(logger: logger)
        Thread.sleep(forTimeInterval: 0.6)
        if !trySend(data) {
            logger.error("Failed to deliver \(request.action.rawValue, privacy: .public) to host")
        }
    }

    private static func trySend(_ data: Data) -> Bool {
        guard let port = CFMessagePortCreateRemote(nil, FinderMenuShared.messagePortName as CFString) else {
            return false
        }
        defer { CFMessagePortInvalidate(port) }
        let status = CFMessagePortSendRequest(port, messageID, data as CFData, sendTimeout, 0.0, nil, nil)
        return status == Int32(kCFMessagePortSuccess)
    }

    private static func launchHost(logger: Logger) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: FinderMenuShared.hostBundleID) else {
            logger.error("Host app not found for bundle id \(FinderMenuShared.hostBundleID, privacy: .public)")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                logger.error("Launch host failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
