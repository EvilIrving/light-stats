import AppKit
import CoreFoundation
import Foundation
import os

nonisolated enum FinderMenuIPCClient {
    private static let messageID: Int32 = 1
    private static let sendTimeout: CFTimeInterval = 0.5

    static func send(_ request: FinderMenuRequest, logger: Logger) async {
        guard let data = request.encoded() else { return }
        if await Task.detached(operation: { trySend(data) }).value { return }
        await launchHost(logger: logger)
        for _ in 0..<10 {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
            guard FinderMenuShared.isEnabled() else { return }
            if await Task.detached(operation: { trySend(data) }).value { return }
        }
        logger.error("Failed to deliver \(request.action.rawValue, privacy: .public) to host")
        FinderMenuShared.writePendingFailure(action: request.action.rawValue)
        DistributedNotificationCenter.default().postNotificationName(
            FinderMenuShared.deliveryFailed, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    private static func trySend(_ data: Data) -> Bool {
        guard let port = CFMessagePortCreateRemote(nil, FinderMenuShared.messagePortName as CFString) else { return false }
        defer { CFMessagePortInvalidate(port) }
        let status = CFMessagePortSendRequest(port, messageID, data as CFData, sendTimeout, 0, nil, nil)
        return status == Int32(kCFMessagePortSuccess)
    }

    @MainActor private static func launchHost(logger: Logger) async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: FinderMenuShared.hostBundleID) else {
            logger.error("Host app not found")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        } catch {
            logger.error("Launch host failed")
        }
    }
}
