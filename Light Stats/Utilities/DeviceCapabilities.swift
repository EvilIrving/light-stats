//
//  DeviceCapabilities.swift
//  Light Stats
//
//  静态硬件能力探测。无状态、与 app 无关，可被任意层调用。
//

import Foundation
import IOKit

enum DeviceCapabilities {

    /// 是否为带内置键盘的便携机型（MacBook 系列）。
    /// 判据：是否存在内置电池——笔记本有，Mac mini / Studio / iMac / Mac Pro 没有。
    /// 比解析 `hw.model` 前缀可靠：Apple Silicon 上 Mac mini 与 MacBook Air 都报
    /// 形如 `MacXX,Y` 的通用标识，无法据此区分。结果是硬件事实，缓存一次即可。
    static let isPortable: Bool = {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return false }
        IOObjectRelease(service)
        return true
    }()
}
