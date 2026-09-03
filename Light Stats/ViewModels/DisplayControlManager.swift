//
//  DisplayControlManager.swift
//  Light Stats
//

import Combine
import Foundation


#if !APP_STORE
@MainActor
final class DisplayControlManager: ObservableObject {
    @Published private(set) var displays: [ControlledDisplay] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var hardwareBrightnessUnavailable = false

    static let shared = DisplayControlManager()

    private static let pollInterval: Duration = .seconds(5)
    private static let gripProtectionInterval: TimeInterval = 4

    private let logger = AppLogger(category: "DisplayControl")
    private let gate: DDCEnvironmentGate
    private let service: DisplayControlService
    private let writeDebouncer: DisplayWriteDebouncer

    private var isEnabled = false
    private var isPanelVisible = false
    private var refreshTask: Task<Void, Never>?
    private var suppressionRetryTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var refreshGeneration = UUID()
    private var pendingValues: [UInt32: Double] = [:]
    private var recentlySetValues: [UInt32: (value: Double, date: Date)] = [:]
    private var lastWrittenValues: [UInt32: Double] = [:]

    init(
        gate: DDCEnvironmentGate = DDCEnvironmentGate(),
        writeDebouncer: DisplayWriteDebouncer? = nil
    ) {
        self.gate = gate
        service = DisplayControlService(gate: gate)
        self.writeDebouncer = writeDebouncer ?? DisplayWriteDebouncer()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        logger.info("Display control \(enabled ? "enabled" : "disabled")")

        if enabled {
            gate.start { [weak self] in
                self?.environmentDidChange()
            }
            Task { @MainActor [weak self] in
                await self?.service.resetHungBus()
                guard let self, self.isEnabled else { return }
                self.refresh()
                self.syncPolling()
            }
        } else {
            stopRuntimeWork(clearDisplays: true)
            if !hardwareBrightnessUnavailable {
                gate.stop()
            }
        }
    }

    func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
        guard isEnabled else { return }
        if visible {
            refresh()
        }
        syncPolling()
    }

    func applicationDidBecomeActive() {
        guard isEnabled, !gate.isSuppressed else { return }
        refresh()
        retryPendingWrites()
    }

    func brightness(displayID: UInt32) -> Double {
        if let pending = pendingValues[displayID] {
            return pending
        }
        if let recent = recentlySetValues[displayID],
           Date().timeIntervalSince(recent.date) < Self.gripProtectionInterval {
            return recent.value
        }
        return displays.first { $0.id == displayID }?.brightness ?? 50
    }

    func setBrightness(_ value: Double, displayID: UInt32) {
        guard let index = displays.firstIndex(where: { $0.id == displayID }),
              displays[index].capability != .unsupported,
              displays[index].capability != .probing
        else {
            return
        }

        let clampedValue = min(100, max(0, value))
        displays[index].brightness = clampedValue
        pendingValues[displayID] = clampedValue
        recentlySetValues[displayID] = (clampedValue, Date())
        scheduleWrite(value: clampedValue, displayID: displayID)
    }

    var adjustableDisplays: [ControlledDisplay] {
        displays.filter(\.isHardwareAdjustable)
    }

    var canEnableHardwareBrightness: Bool {
        !hardwareBrightnessUnavailable
    }

    func isAdjustable(displayID: UInt32) -> Bool {
        displays.first { $0.id == displayID }?.isHardwareAdjustable == true
    }

    func stop() {
        isEnabled = false
        hardwareBrightnessUnavailable = false
        gate.stop()
        stopRuntimeWork(clearDisplays: true)
    }

    private func refresh() {
        guard isEnabled else { return }
        guard !gate.isSuppressed else {
            logger.debug("Refresh deferred: environment gate suppressed")
            scheduleSuppressionRetry()
            return
        }
        guard !isRefreshing else {
            logger.debug("Refresh skipped: another refresh is in flight")
            return
        }
        suppressionRetryTask?.cancel()
        suppressionRetryTask = nil
        refreshTask?.cancel()
        refreshGeneration = UUID()
        let generation = refreshGeneration
        isRefreshing = true

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let detected = await service.discoverDisplays()
            guard !Task.isCancelled,
                  self.isEnabled,
                  generation == self.refreshGeneration
            else {
                if generation == self.refreshGeneration {
                    self.isRefreshing = false
                }
                return
            }

            self.displays = detected.map { display in
                var result = display
                result.brightness = self.protectedBrightness(for: display)
                return result
            }
            self.publishAvailability()
            self.pruneTransientState()
            self.isRefreshing = false
            self.retryPendingWrites()
        }
    }

    private func protectedBrightness(for display: ControlledDisplay) -> Double {
        if let pending = pendingValues[display.id] {
            return pending
        }
        if let recent = recentlySetValues[display.id],
           Date().timeIntervalSince(recent.date) < Self.gripProtectionInterval {
            return recent.value
        }
        return display.brightness
    }

    private func scheduleSuppressionRetry() {
        guard suppressionRetryTask == nil else { return }
        suppressionRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.suppressionRetryTask = nil
            self.refresh()
        }
    }

    private func syncPolling() {
        pollTask?.cancel()
        pollTask = nil
        guard isEnabled, isPanelVisible else { return }

        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                await self?.pollBrightness()
            }
        }
    }

    private func pollBrightness() async {
        guard isEnabled, isPanelVisible, !gate.isSuppressed else { return }
        let displayIDs = adjustableDisplays.map(\.id)
        for displayID in displayIDs {
            guard pendingValues[displayID] == nil,
                  !isGripProtected(displayID: displayID),
                  let index = displays.firstIndex(where: { $0.id == displayID })
            else {
                continue
            }
            if let brightness = await service.readBrightness(displayID: displayID) {
                displays[index].brightness = brightness
                continue
            }
            if await service.capability(displayID: displayID) == .unsupported {
                displays[index].capability = .unsupported
                pruneTransientState()
                publishAvailability()
            }
        }
    }

    private func isGripProtected(displayID: UInt32) -> Bool {
        guard let recent = recentlySetValues[displayID] else { return false }
        return Date().timeIntervalSince(recent.date) < Self.gripProtectionInterval
    }

    private func scheduleWrite(value: Double, displayID: UInt32) {
        writeDebouncer.submit(displayID: displayID, value: value) { [weak self] latestValue in
            await self?.performWrite(value: latestValue, displayID: displayID)
        }
    }

    private func performWrite(value: Double, displayID: UInt32) async {
        guard isEnabled else { return }
        guard !gate.isSuppressed else {
            pendingValues[displayID] = value
            return
        }

        if let lastValue = lastWrittenValues[displayID], abs(lastValue - value) < 0.001 {
            clearPendingValue(value, displayID: displayID)
            return
        }

        let success = await service.setBrightness(value, displayID: displayID)
        if success {
            lastWrittenValues[displayID] = value
        } else {
            logger.error("Brightness write failed for display \(displayID)")
            if await service.capability(displayID: displayID) == .unsupported,
               let index = displays.firstIndex(where: { $0.id == displayID }) {
                displays[index].capability = .unsupported
                pruneTransientState()
                publishAvailability()
                return
            }
        }
        clearPendingValue(value, displayID: displayID)
    }

    private func clearPendingValue(_ value: Double, displayID: UInt32) {
        guard let pending = pendingValues[displayID], abs(pending - value) < 0.001 else { return }
        pendingValues[displayID] = nil
    }

    private func retryPendingWrites() {
        guard isEnabled, !gate.isSuppressed else { return }
        for (displayID, value) in pendingValues {
            scheduleWrite(value: value, displayID: displayID)
        }
    }

    private func environmentDidChange() {
        hardwareBrightnessUnavailable = false
        if !isEnabled {
            gate.stop()
            return
        }
        Task { @MainActor [weak self] in
            await self?.service.resetHungBus()
            guard let self, self.isEnabled else { return }
            self.refresh()
            self.retryPendingWrites()
        }
    }

    private func publishAvailability() {
        let available = displays.contains(where: \.isHardwareAdjustable)
        hardwareBrightnessUnavailable = !available
        guard !available, SettingsManager.shared.displayBrightnessControlEnabled else { return }
        SettingsManager.shared.displayBrightnessControlEnabled = false
    }

    private func pruneTransientState() {
        let adjustableIDs = Set(displays.filter(\.isHardwareAdjustable).map(\.id))
        pendingValues = pendingValues.filter { adjustableIDs.contains($0.key) }
        recentlySetValues = recentlySetValues.filter { adjustableIDs.contains($0.key) }
        lastWrittenValues = lastWrittenValues.filter { adjustableIDs.contains($0.key) }
    }

    private func stopRuntimeWork(clearDisplays: Bool) {
        refreshGeneration = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        suppressionRetryTask?.cancel()
        suppressionRetryTask = nil
        pollTask?.cancel()
        pollTask = nil
        writeDebouncer.cancelAll()
        pendingValues.removeAll()
        recentlySetValues.removeAll()
        lastWrittenValues.removeAll()
        isRefreshing = false
        if clearDisplays {
            displays.removeAll()
        }
        Task {
            await service.stop()
        }
    }
}

#else
/// MAS stub — private display frameworks are not linked in App Store builds.
@MainActor
final class DisplayControlManager: ObservableObject {
    static let shared = DisplayControlManager()

    @Published private(set) var displays: [ControlledDisplay] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var hardwareBrightnessUnavailable = true

    func setEnabled(_ enabled: Bool) {}
    func setPanelVisible(_ visible: Bool) {}
    func applicationDidBecomeActive() {}
    func brightness(displayID: UInt32) -> Double { 50 }
    func setBrightness(_ value: Double, displayID: UInt32) {}
    var adjustableDisplays: [ControlledDisplay] { [] }
    var canEnableHardwareBrightness: Bool { false }
    func isAdjustable(displayID: UInt32) -> Bool { false }
    func stop() {}
}
#endif
