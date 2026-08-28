//
//  FindMouseCoordinator.swift
//  Light Stats
//
//  Settings → FindMouseService wiring. Lives in ViewModels so the service
//  never imports SettingsManager.
//

import Combine
import Foundation

@MainActor
final class FindMouseCoordinator {
    private let settings: SettingsManager
    private let service: FindMouseControlling
    private let license: LicenseManager
    private var permissionAlertShown = false
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsManager, service: FindMouseControlling, license: LicenseManager = .shared) {
        self.settings = settings
        self.service = service
        self.license = license
    }

    func start() {
        observe()
        sync()
    }

    /// Permission may have been granted while we were in the background.
    func retryIfNeeded() {
        guard settings.findMouseEnabled, license.isFindMouseUnlocked, !service.isRunning else { return }
        service.updateTriggerKey(settings.findMouseTriggerKey)
        _ = service.start()
    }

    func stop() {
        service.stop()
    }

    private func observe() {
        settings.$findMouseEnabled
            .combineLatest(license.$payload)
            .dropFirst()
            .sink { [weak self] isEnabled, payload in
                self?.permissionAlertShown = false
                self?.sync(isEnabled: isEnabled, payload: payload)
            }
            .store(in: &cancellables)

        settings.$findMouseTriggerKey
            .dropFirst()
            .sink { [weak self] key in
                guard let self else { return }
                sync(isEnabled: settings.findMouseEnabled, payload: license.payload, triggerKey: key)
            }
            .store(in: &cancellables)
    }

    private func sync() {
        sync(
            isEnabled: settings.findMouseEnabled,
            payload: license.payload,
            triggerKey: settings.findMouseTriggerKey
        )
    }

    /// 接收 publisher 的新值而不是回读 `@Published` 属性；Combine 在属性写入前发送，
    /// 回读会看到旧激活状态，导致移除授权后服务不停止。
    private func sync(isEnabled: Bool, payload: LicensePayload?, triggerKey: FindMouseTriggerKey? = nil) {
        let isUnlocked = license.isGrandfathered || payload?.features.contains(.findMouse) == true
        if isEnabled, isUnlocked {
            service.updateTriggerKey(triggerKey ?? settings.findMouseTriggerKey)
            startOrPrompt()
        } else {
            service.stop()
        }
    }

    private func startOrPrompt() {
        guard !service.isRunning else { return }
        if service.start() { return }
        presentPermissionAlert()
    }

    private func presentPermissionAlert() {
        guard !permissionAlertShown else { return }
        permissionAlertShown = true
        AccessibilityPermission.presentSettingsAlert(
            title: "settings.findMouse.permissionTitle".localized,
            message: "settings.findMouse.permissionMessage".localized
        )
    }
}
