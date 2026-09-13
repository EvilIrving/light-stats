//
//  DefaultInputSourceCoordinator.swift
//  Light Stats
//
//  Settings → DefaultInputSourceService wiring. Lives in ViewModels so the service
//  never imports SettingsManager. Mirrors FindMouseCoordinator.
//

import Combine
import Foundation

@MainActor
final class DefaultInputSourceCoordinator: ObservableObject {

    static let shared = DefaultInputSourceCoordinator()

    /// 当前系统里可选的输入源，供设置页选择器使用。
    @Published private(set) var availableSources: [InputSourceOption] = []

    private let settings: SettingsManager
    private let service: DefaultInputSourceControlling
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsManager = .shared, service: DefaultInputSourceControlling? = nil) {
        self.settings = settings
        self.service = service ?? DefaultInputSourceService()
    }

    func start() {
        refreshAvailableSources()
        observe()
        sync(isEnabled: settings.defaultInputSourceEnabled, id: settings.defaultInputSourceID)
    }

    func stop() {
        service.stop()
        cancellables.removeAll()
    }

    /// 系统输入源列表会随用户在「系统设置 › 键盘 › 输入法」里的增删变化，
    /// 每次进入设置页刷新一次。
    func refreshAvailableSources() {
        availableSources = DefaultInputSourceService.availableInputSources()
    }

    /// 用户开启开关但还没选过目标：以当前输入源作为默认值 —— 「保持现在这一个」。
    /// 关掉再开不会重设，避免覆盖用户已经做出的选择。
    func seedTargetFromCurrentSourceIfNeeded() {
        guard settings.defaultInputSourceID == nil else { return }
        guard let current = service.currentInputSourceID() else { return }
        settings.defaultInputSourceID = current
    }

    // MARK: - Private

    private func observe() {
        // Combine 在 `@Published` 属性写入前发送，所以必须用发出来的值而不是回读属性：
        // 回读会拿到旧的 enabled / id，导致关掉开关后服务不停（FindMouseCoordinator 同坑）。
        settings.$defaultInputSourceEnabled
            .combineLatest(settings.$defaultInputSourceID)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled, id in self?.sync(isEnabled: isEnabled, id: id) }
            .store(in: &cancellables)
    }

    private func sync(isEnabled: Bool, id: String?) {
        guard isEnabled else {
            service.stop()
            return
        }
        service.updateTarget(id: id)
        guard service.start() else {
            // 目标未选定，或该输入法已被系统移除。保持开关开启、服务停摆，
            // 等用户在设置页选一个可用的（UI 会把失效项标出来）。
            service.stop()
            return
        }
        service.applyNow()
    }
}
