//
//  KeepAwakeService.swift
//  Light Stats
//
//  Created on 2026/06/28.
//
//  保持唤醒：空闲息屏用 IOPMAssertion（caffeinate -d/-i），插电合盖无外接屏时
//  再挂一块运行时虚拟屏，让 WindowServer 走进官方闭盖模式。opt-in、默认关闭。
//  拔电或关掉开关立即拆掉虚拟屏，合盖恢复正常睡眠。
//

import CoreGraphics
import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// 保持唤醒的生命周期服务。Shape C：显式 start()/stop()，由 AppDelegate
/// 在 `keepAwakeEnabled` 开关变化时驱动。无 CGEventTap、无辅助功能权限。
@MainActor
final class KeepAwakeService {

    static let shared = KeepAwakeService()

    private(set) var isRunning = false

    /// Tests flip this off so XCTest does not spawn a system virtual display.
    var usesClamshellDisplay = true

    private var displayAssertionID = IOPMAssertionID(0)
    private var systemAssertionID = IOPMAssertionID(0)
    private var powerSourceLoop: CFRunLoopSource?
    private var displayCallbackRegistered = false
    private var isSyncingClamshell = false
    private let virtualDisplay = VirtualDisplaySession()
    private let log = AppLogger(category: "KeepAwake")

    private init() {}

    /// 持有断言并在需要时挂上闭盖虚拟屏。已在运行则幂等返回 true；显示断言失败返回 false。
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard holdAssertions() else { return false }
        isRunning = true
        startObserversIfNeeded()
        syncClamshellDisplay()
        log.info("keep-awake on")
        return true
    }

    /// 释放断言并拆掉虚拟屏。未运行则无操作。
    func stop() {
        guard isRunning else { return }
        stopObservers()
        virtualDisplay.stop()
        releaseAssertions()
        isRunning = false
        log.info("keep-awake off")
    }

    static func needsClamshellDisplay(
        isPortable: Bool,
        onAC: Bool,
        hasForeignExternal: Bool
    ) -> Bool {
        isPortable && onAC && !hasForeignExternal
    }

    func handlePowerSourceChange() {
        syncClamshellDisplay()
    }

    func handleDisplayReconfiguration(_ flags: CGDisplayChangeSummaryFlags) {
        guard Self.shouldSyncAfterDisplayChange(flags) else { return }
        syncClamshellDisplay()
    }

    /// WindowServer calls the reconfig callback first with
    /// `kCGDisplayBeginConfigurationFlag` (1 << 0), while lists are mid-transaction.
    /// Do not add/remove displays in that phase.
    static func shouldSyncAfterDisplayChange(_ flags: CGDisplayChangeSummaryFlags) -> Bool {
        !flags.contains(CGDisplayChangeSummaryFlags(rawValue: 1 << 0))
    }

    // MARK: - Assertions

    private func holdAssertions() -> Bool {
        var displayID = IOPMAssertionID(0)
        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Light Stats keep awake" as CFString,
            &displayID
        )
        guard displayResult == kIOReturnSuccess else {
            log.error("keep-awake display assertion failed: \(displayResult)")
            return false
        }
        displayAssertionID = displayID

        var systemID = IOPMAssertionID(0)
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Light Stats keep awake (system)" as CFString,
            &systemID
        )
        if systemResult == kIOReturnSuccess {
            systemAssertionID = systemID
        } else {
            log.error("keep-awake system assertion failed: \(systemResult)")
        }
        return true
    }

    private func releaseAssertions() {
        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
        if systemAssertionID != 0 {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
        }
    }

    // MARK: - Clamshell display

    private func syncClamshellDisplay() {
        guard isRunning, usesClamshellDisplay else {
            virtualDisplay.stop()
            return
        }
        guard !isSyncingClamshell else { return }
        isSyncingClamshell = true
        defer { isSyncingClamshell = false }

        let needed = Self.needsClamshellDisplay(
            isPortable: DeviceCapabilities.isPortable,
            onAC: Self.isOnACPower(),
            hasForeignExternal: VirtualDisplaySession.hasForeignExternalDisplay(
                excluding: virtualDisplay.displayID
            )
        )
        if needed {
            if virtualDisplay.isActive { return }
            if virtualDisplay.start() {
                log.info("keep-awake clamshell display on id=\(virtualDisplay.displayID ?? 0)")
            } else {
                log.error("keep-awake clamshell display failed")
            }
        } else if virtualDisplay.isActive {
            virtualDisplay.stop()
            log.info("keep-awake clamshell display off")
        }
    }

    private static func isOnACPower() -> Bool {
        isOnACPower(batteryPowerState: internalBatteryPowerState())
    }

    /// Missing snapshot or battery row is not AC, so the dummy display is torn down.
    static func isOnACPower(batteryPowerState: String?) -> Bool {
        batteryPowerState == kIOPSACPowerValue
    }

    private static func internalBatteryPowerState() -> String? {
        guard let snapshotRef = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourcesRef = IOPSCopyPowerSourcesList(snapshotRef)?.takeRetainedValue()
                as? [CFTypeRef] else {
            return nil
        }
        for source in sourcesRef {
            guard let desc = IOPSGetPowerSourceDescription(snapshotRef, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                return desc[kIOPSPowerSourceStateKey] as? String
            }
        }
        return nil
    }

    // MARK: - Observers

    private func startObserversIfNeeded() {
        guard usesClamshellDisplay else { return }
        if powerSourceLoop == nil {
            let source = IOPSNotificationCreateRunLoopSource(keepAwakePowerSourceChanged, nil)?
                .takeRetainedValue()
            if let source {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                powerSourceLoop = source
            }
        }
        if !displayCallbackRegistered {
            let err = CGDisplayRegisterReconfigurationCallback(keepAwakeDisplayReconfigured, nil)
            if err == .success {
                displayCallbackRegistered = true
            } else {
                log.error("keep-awake display callback failed: \(err.rawValue)")
            }
        }
    }

    private func stopObservers() {
        if let powerSourceLoop {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceLoop, .commonModes)
            self.powerSourceLoop = nil
        }
        if displayCallbackRegistered {
            CGDisplayRemoveReconfigurationCallback(keepAwakeDisplayReconfigured, nil)
            displayCallbackRegistered = false
        }
    }
}

nonisolated private func keepAwakePowerSourceChanged(_: UnsafeMutableRawPointer?) {
    Task { @MainActor in
        KeepAwakeService.shared.handlePowerSourceChange()
    }
}

nonisolated private func keepAwakeDisplayReconfigured(
    _: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _: UnsafeMutableRawPointer?
) {
    Task { @MainActor in
        KeepAwakeService.shared.handleDisplayReconfiguration(flags)
    }
}
