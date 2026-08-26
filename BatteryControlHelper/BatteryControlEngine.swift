import Foundation
import IOKit
import IOKit.pwr_mgt
import os

@MainActor
final class BatteryControlEngine {
    private static let canSystemSleepMessage: UInt32 = (UInt32(0x38) << 26) | UInt32(0x270)
    private static let systemWillSleepMessage: UInt32 = (UInt32(0x38) << 26) | UInt32(0x280)
    private static let systemHasPoweredOnMessage: UInt32 = (UInt32(0x38) << 26) | UInt32(0x300)

    private let log = Logger(subsystem: BatteryControlIPC.helperBundleIdentifier, category: "Engine")
    private let smc = BatteryControlSMC()
    private let store = BatteryControlConfigurationStore()
    private var configuration: StoredBatteryControlConfiguration
    private var timer: Timer?
    private var wakeTimer: Timer?
    private var powerRootPort: io_connect_t = 0
    private var powerNotificationPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0
    private var activeConnectionGeneration: Int64 = -1
    private var latestRequestRevision: Int64 = -1

    private(set) var statusCode: BatteryControlStatusCode = .unavailable
    private(set) var lastError: String?

    init() {
        configuration = store.load()
        if smc.backend == .legacy {
            registerPowerNotifications()
        }
        timer = Timer.scheduledTimer(
            timeInterval: 10,
            target: BatteryControlTimerTarget { [weak self] in self?.reconcile() },
            selector: #selector(BatteryControlTimerTarget.fire),
            userInfo: nil,
            repeats: true
        )
        reconcile()
    }

    func acceptRequest(connectionGeneration: Int64, revision: Int64) -> Bool {
        if connectionGeneration > activeConnectionGeneration {
            activeConnectionGeneration = connectionGeneration
            latestRequestRevision = revision
            return true
        }
        guard connectionGeneration == activeConnectionGeneration,
              revision > latestRequestRevision else {
            return false
        }
        latestRequestRevision = revision
        return true
    }

    func configure(enabled: Bool, upperLimit: Int, lowerLimit: Int) -> (Bool, String?) {
        guard isValid(upperLimit: upperLimit, lowerLimit: lowerLimit) else {
            return fail("Invalid charge limits")
        }
        if !enabled {
            return reset()
        }
        guard smc.backend != .unknown else {
            statusCode = .unavailable
            return fail("This Mac does not expose a supported charge-control backend")
        }
        configuration = StoredBatteryControlConfiguration(
            enabled: true,
            upperLimit: upperLimit,
            lowerLimit: lowerLimit
        )
        do {
            try store.save(configuration)
            try reconcileOrThrow()
            return (true, nil)
        } catch {
            return fail(error.localizedDescription)
        }
    }

    func reset() -> (Bool, String?) {
        do {
            if smc.backend == .legacy {
                try smc.enableLegacyCharging()
            } else if smc.backend == .firmware {
                try smc.disableFirmwareLimit()
            }
            configuration = .disabled
            try store.clear()
            statusCode = .disabled
            lastError = nil
            return (true, nil)
        } catch {
            return fail(error.localizedDescription)
        }
    }

    func status() -> (Int, Int, Int, Int, Int, Bool, String?) {
        let power = BatteryPowerSourceReader.current()
        return (
            statusCode.rawValue,
            smc.backend.rawValue,
            power?.percent ?? -1,
            configuration.upperLimit,
            configuration.lowerLimit,
            smc.backend != .unknown,
            lastError
        )
    }

    func reconcile() {
        do {
            try reconcileOrThrow()
        } catch {
            _ = fail(error.localizedDescription)
        }
    }

    private func reconcileOrThrow() throws {
        guard configuration.enabled else {
            statusCode = .disabled
            lastError = nil
            return
        }
        guard smc.backend != .unknown else {
            statusCode = .unavailable
            throw BatteryControlEngineError.unsupported
        }
        guard let power = BatteryPowerSourceReader.current() else {
            statusCode = .unavailable
            throw BatteryControlEngineError.noBattery
        }
        guard power.onACPower else {
            statusCode = .discharging
            lastError = nil
            return
        }

        switch smc.backend {
        case .firmware:
            if configuration.upperLimit >= 100 {
                try smc.disableFirmwareLimit()
            } else {
                try smc.setFirmwareLimit(
                    lower: configuration.lowerLimit,
                    upper: configuration.upperLimit
                )
            }
            statusCode = power.isCharging ? .charging : .holding
        case .legacy:
            let chargingEnabled = try smc.isLegacyChargingEnabled()
            let shouldEnable = BatteryControlLegacyPolicy.shouldEnableCharging(
                percent: power.percent,
                upperLimit: configuration.upperLimit,
                lowerLimit: configuration.lowerLimit,
                currentlyEnabled: chargingEnabled
            )
            if shouldEnable != chargingEnabled {
                if shouldEnable {
                    try smc.enableLegacyCharging()
                } else {
                    try smc.disableLegacyCharging()
                }
            }
            statusCode = shouldEnable ? .charging : .holding
        case .unknown:
            statusCode = .unavailable
            throw BatteryControlEngineError.unsupported
        }
        lastError = nil
    }

    private func isValid(upperLimit: Int, lowerLimit: Int) -> Bool {
        BatteryControlLimits.isValid(upper: upperLimit, lower: lowerLimit)
    }

    private func fail(_ message: String) -> (Bool, String?) {
        statusCode = .error
        lastError = message
        log.error("Battery control failed: \(message, privacy: .public)")
        return (false, message)
    }

    private func registerPowerNotifications() {
        let result = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &powerNotificationPort,
            batteryControlPowerCallback,
            &powerNotifier
        )
        guard result != 0, let powerNotificationPort else {
            log.error("Power notification registration failed")
            return
        }
        powerRootPort = result
        if let source = IONotificationPortGetRunLoopSource(powerNotificationPort)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func unregisterPowerNotifications() {
        guard powerNotifier != 0 else { return }
        IODeregisterForSystemPower(&powerNotifier)
        powerNotifier = 0
        if let powerNotificationPort {
            if let source = IONotificationPortGetRunLoopSource(powerNotificationPort)?.takeUnretainedValue() {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            IONotificationPortDestroy(powerNotificationPort)
            self.powerNotificationPort = nil
        }
        if powerRootPort != 0 {
            IOServiceClose(powerRootPort)
            powerRootPort = 0
        }
    }

    fileprivate func handlePowerMessage(_ messageType: UInt32, notificationID: Int) {
        switch messageType {
        case Self.canSystemSleepMessage:
            allowPowerChange(notificationID)
        case Self.systemWillSleepMessage:
            if configuration.enabled, smc.backend == .legacy {
                do {
                    try reconcileOrThrow()
                } catch {
                    _ = fail(error.localizedDescription)
                }
            }
            allowPowerChange(notificationID)
        case Self.systemHasPoweredOnMessage:
            wakeTimer?.invalidate()
            let target = BatteryControlTimerTarget { [weak self] in self?.reconcile() }
            wakeTimer = Timer.scheduledTimer(
                timeInterval: 30,
                target: target,
                selector: #selector(BatteryControlTimerTarget.fire),
                userInfo: nil,
                repeats: false
            )
        default:
            break
        }
    }

    private func allowPowerChange(_ notificationID: Int) {
        guard powerRootPort != 0 else { return }
        _ = IOAllowPowerChange(powerRootPort, intptr_t(notificationID))
    }
}

private enum BatteryControlEngineError: LocalizedError {
    case unsupported
    case noBattery

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Charge control is unsupported on this Mac"
        case .noBattery:
            return "No internal battery was found"
        }
    }
}

@MainActor
private final class BatteryControlTimerTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire() {
        action()
    }
}

private nonisolated func batteryControlPowerCallback(
    _ refcon: UnsafeMutableRawPointer?,
    _: io_service_t,
    _ messageType: UInt32,
    _ messageArgument: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let engine = Unmanaged<BatteryControlEngine>.fromOpaque(refcon).takeUnretainedValue()
    let notificationID = Int(bitPattern: messageArgument)
    // Callback is scheduled on the main run loop (see registerPowerNotifications).
    // Sleep messages must be acknowledged before this function returns.
    MainActor.assumeIsolated {
        engine.handlePowerMessage(messageType, notificationID: notificationID)
    }
}
