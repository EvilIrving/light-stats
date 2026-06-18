//
//  CleaningModeViewModel.swift
//  Light Stats
//
//  清洁模式协调层（@MainActor）：管理权限检查、键盘锁定服务、60 秒硬超时倒计时，
//  并通知遮罩窗口显示/关闭。倒计时 Timer 与 KeyboardLockService 的 tap 健康状态
//  完全解耦——无论 tap 是否异常，到点都会无条件退出，避免用户被锁死。
//

import AppKit
import Combine
import OSLog

@MainActor
final class CleaningModeViewModel: ObservableObject {

    static let shared = CleaningModeViewModel()

    static let duration = 60

    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds = CleaningModeViewModel.duration

    private let service: KeyboardLocking
    private let logger = Logger(subsystem: "com.lightstats", category: "CleaningMode")
    private var countdownTimer: Timer?

    init(service: KeyboardLocking = KeyboardLockService()) {
        self.service = service
    }

    // MARK: - 入口

    func start() {
        guard !isActive else { return }

        guard service.checkPermission(promptIfNeeded: true) else {
            logger.notice("Accessibility permission not granted, showing prompt")
            presentPermissionAlert()
            return
        }

        guard service.start() else {
            logger.error("Failed to start keyboard event tap")
            return
        }

        remainingSeconds = Self.duration
        isActive = true
        startCountdown()
    }

    func requestEarlyStop() {
        stop()
    }

    private func stop() {
        guard isActive else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        service.stop()
        isActive = false
    }

    // MARK: - 倒计时

    private func startCountdown() {
        countdownTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func tick() {
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            stop()
        }
    }

    // MARK: - 权限提示

    private func presentPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "cleaning.permission.title".localized
        alert.informativeText = "cleaning.permission.message".localized
        alert.addButton(withTitle: "cleaning.permission.openSettings".localized)
        alert.addButton(withTitle: "update.action.later".localized)
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
