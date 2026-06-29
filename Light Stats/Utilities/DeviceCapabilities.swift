//
//  DeviceCapabilities.swift
//  Light Stats
//
//  静态硬件能力探测。无状态、与 app 无关，可被任意层调用。
//

import Foundation
import IOKit.ps

enum DeviceCapabilities {

    /// 是否为带内置键盘的便携机型（MacBook 系列）。
    /// 判据：是否存在「内置电池」电源——笔记本有，Mac mini / Studio / iMac / Mac Pro 没有。
    ///
    /// 不能用 `IOServiceMatching("AppleSmartBattery")`：Apple Silicon 的 Mac mini（如 M4
    /// Mac16,10）也会注册一个 `AppleSmartBattery` 服务，但其 `MaxCapacity == 0`，并无真实电池，
    /// 会把台式机误判为便携机。改用 `IOPSCopyPowerSourcesList`——台式机上为空，与
    /// `PowerService.readPowerSources()` 保持同一判据。结果是硬件事实，缓存一次即可。
    static let isPortable: Bool = {
        guard let snapshotRef = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourcesRef = IOPSCopyPowerSourcesList(snapshotRef)?.takeRetainedValue()
                as? [CFTypeRef] else {
            return false
        }
        for source in sourcesRef {
            guard let desc = IOPSGetPowerSourceDescription(snapshotRef, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                return true
            }
        }
        return false
    }()
}
