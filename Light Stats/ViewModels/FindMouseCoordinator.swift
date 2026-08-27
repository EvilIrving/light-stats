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
    private var permissionAlertShown = false
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsManager, service: FindMouseControlling) {
        self.settings = settings
        self.service = service
    }

    func start() {
        observe()
        sync()
    }

    /// Permission may have been granted while we were in the background.
    func retryIfNeeded() {
        guard settings.findMouseEnabled, !service.isRunning else { return }
        service.updateTriggerKey(settings.findMouseTriggerKey)
        _ = service.start()
    }

    func stop() {
        service.stop()
    }

    private func observe() {
        settings.$findMouseEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.permissionAlertShown = false
                self?.sync()
            }
            .store(in: &cancellables)

        settings.$findMouseTriggerKey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)
    }

    private func sync() {
        if settings.findMouseEnabled {
            service.updateTriggerKey(settings.findMouseTriggerKey)
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
