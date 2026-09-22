//
//  BatteryHardwarePolicy.swift
//  Light Stats
//
//  Machine-level battery presence. Hide battery surfaces when there is no
//  internal battery — same rule shape as FanHardwarePolicy / noFanKeys.
//

import Foundation

enum BatteryHardwarePolicy {

    /// Whether status bar / Overview / Monitoring settings should expose battery UI.
    ///
    /// `hasInternalBattery` is the hardware fact from `DeviceCapabilities.isPortable`
    /// (IOPS internal-battery source). A live `.noBattery` reading alone is not the
    /// signal we gate on here: that value currently also covers empty power-source
    /// lists, and AppleSmartBattery presence alone false-positives on some desktops.
    nonisolated static func shouldShowSurfaces(hasInternalBattery: Bool) -> Bool {
        hasInternalBattery
    }
}
