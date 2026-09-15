//
//  ScreenRecordingPermission.swift
//  Light Stats
//

import AppKit
import CoreGraphics
import OSLog

/// 屏幕录制权限的统一入口，形态与 `AccessibilityPermission` 对称。
///
/// 只有「拿到窗口的真实像素」需要它：窗口标题、位置、层级走 Accessibility / CGWindowList 就能拿到，
/// 而缩略图、Dock 悬停预览、Cmd-Tab Plus 的截图全部经 ScreenCaptureKit，由 TCC 门控。
///
/// 一个必须提前知道的系统行为：**授权之后通常要重启 App 才会生效**。
/// `CGPreflightScreenCaptureAccess()` 在进程启动时缓存了判定，用户在系统设置里打开开关后，
/// 当前进程往往仍读到 false。所以这里把「已授权但需要重启」做成一个独立状态，
/// 而不是让界面一直停在「未授权」上骗用户。
nonisolated enum ScreenRecordingPermission {

    private static let log = AppLogger(category: "ScreenRecordingPermission")

    /// 系统设置 → 隐私与安全性 → 屏幕录制。
    static let settingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    /// 当前进程是否已获授权。纯检查，不弹任何窗口。
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 请求授权。系统只在**首次**弹窗；之后必须由用户去系统设置手动打开。
    ///
    /// - Returns: 调用后是否已授权。返回 `false` 不代表失败——多数情况是系统弹窗还没被处理，
    ///   或者用户需要去系统设置里打开。
    @discardableResult
    static func request() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        log.info("Screen recording permission requested, granted=\(granted)")
        DiagnosticLogService.record(
            category: "windowManagement",
            action: "screenRecordingRequested",
            fields: ["granted": granted ? "true" : "false"]
        )
        return granted
    }

    /// 本次进程启动后是否走过授权流程。
    ///
    /// 界面上区分「没授权」与「授权了但要重启」全靠这一个标记：系统没有公开 API 读那个开关，
    /// 而我们一旦申请过、用户也回来了，进程内判定仍是 false 就只能解释为要重启。
    /// 纯 syscall 与开关状态，标成锁保护的小盒子而不是 actor，因为它要在设置页同步读。
    static var hasBeenRequested: Bool {
        requestLog.hasRequested
    }

    static func markRequested() {
        requestLog.markRequested()
    }

    private static let requestLog = ScreenRecordingRequestLog()

    /// 跳转系统设置的屏幕录制页。
    @MainActor
    static func openSettings() {
        guard let url = URL(string: settingsURLString) else {
            log.error("Failed to build Screen Recording settings URL")
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// 一次进程生命周期内的授权流程标记。
nonisolated final class ScreenRecordingRequestLog: @unchecked Sendable {

    private let lock = NSLock()
    private var requested = false

    var hasRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    func markRequested() {
        lock.lock()
        requested = true
        lock.unlock()
    }
}

/// 屏幕录制权限在界面上需要表达的四种状态。
///
/// 两态（有/没有）不够用：用户刚在系统设置里打开开关，而当前进程还没重新读取判定时，
/// 说「未授权」是错的，说「已授权」也是错的——真实情况是「授权了，但需要重启」。
enum ScreenRecordingAuthorization: String, Sendable, CaseIterable {

    /// 当前进程可以使用屏幕捕获。
    case authorized
    /// 明确没有授权。
    case denied
    /// 系统里已经打开，但当前进程读不到——需要重启 App。
    case requiresRestart

    /// 决定状态的唯一规则，抽出来是为了可测。
    ///
    /// 进程内判定说没有、而这个进程从来没申请过，那是真的没授权。
    /// 申请过之后仍然读到没有，只可能是「用户在系统设置里打开了，但本进程还没重新读取判定」——
    /// 也就是要重启。这个区分是界面上唯一能让用户知道下一步该做什么的东西。
    static func resolve(isGranted: Bool, hasRequestedThisSession: Bool) -> ScreenRecordingAuthorization {
        if isGranted { return .authorized }
        return hasRequestedThisSession ? .requiresRestart : .denied
    }
}

/// 重启自己。
///
/// 屏幕录制授权生效需要重启进程，而让用户自己去退出再打开，是把系统的毛病转嫁给用户。
/// 只有在确认新实例能起来之后才退出当前进程，否则用户会得到一个关掉就再也不回来的 App。
///
/// 失败时不自己弹提示：`ApplicationRelaunch` 在 Services 层，而提示是界面的事。
/// 调用方通过 `onFailure` 决定怎么告诉用户。
@MainActor
enum ApplicationRelaunch {

    private static let log = AppLogger(category: "Relaunch")

    static func relaunch(onFailure: @escaping @MainActor (String) -> Void) {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
            Task { @MainActor in
                guard application != nil, error == nil else {
                    let reason = error?.localizedDescription ?? "unknown"
                    log.error("Relaunch failed, staying alive: \(reason)")
                    onFailure(reason)
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
