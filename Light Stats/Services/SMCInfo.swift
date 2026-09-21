//
//  SMCInfo.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation
import IOKit

/// SMC access for temperature and fan speed
/// Based on AppleSMC.kext interface - struct size must be exactly 80 bytes
enum SMCInfo {

    // SMC connection (persistent across reads)
    private static var conn: io_connect_t = 0
    /// Serialises open/close/invalidate so concurrent reads cannot race connection state.
    private static let connLock = NSLock()

    // Temperature cache for stability (with thread safety)
    private static let temperatureLock = NSLock()
    private static var _cachedTemperature: Double?
    private static var _cacheTimestamp: Date?
    private static let maxCacheAge: TimeInterval = 10  // 10 seconds

    // MARK: - Probe results

    /// 温度探测的原因码（写进诊断日志，支持报告据此解释「为什么没有温度」）。
    enum TemperatureReason {
        static let keysRead = "keysRead"
        static let connectionUnavailable = "connectionUnavailable"
        static let usingCachedValue = "usingCachedValue"
        static let reconnectFailed = "reconnectFailed"
        static let usingCachedAfterReconnectFailure = "usingCachedAfterReconnectFailure"
        static let noValidTemperatureKeys = "noValidTemperatureKeys"
        static let usingCachedAfterEmptyRead = "usingCachedAfterEmptyRead"
    }

    struct TemperatureProbe: Sendable, Equatable {
        let celsius: Double?
        let reasonCode: String
        /// 本轮接受的有效温度键数量；走缓存时为 0。
        let acceptedKeyCount: Int
        let usedCachedValue: Bool

        /// 报告在 `probeCollectionEnabled == false` 时使用的占位：没有采集过，不等于读不到。
        static let notCollected = TemperatureProbe(
            celsius: nil,
            reasonCode: "notCollected",
            acceptedKeyCount: 0,
            usedCachedValue: false
        )
    }

    /// SMC 键读取结果：区分「键不存在」和「键在但读失败」。
    enum KeyReadOutcome: String, Sendable, Equatable {
        case value
        case missing
        case failed
    }

    // MARK: - SMC Selectors
    private static let kSMCReadKey: UInt8 = 5
    private static let kSMCGetKeyInfo: UInt8 = 9

    // MARK: - Public API

    private static let smcDebugEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["LIGHT_STATS_SMC_DEBUG"] == "1"
        #else
        return false
        #endif
    }()

    private static func writeDebugLog(_ content: String) {
        guard smcDebugEnabled else { return }
        #if DEBUG
        let path = "/tmp/light-stats-smc-debug.log"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        #endif
    }

    static func getCPUTemperature() -> Double? {
        getCPUTemperatureProbe().celsius
    }

    /// 温度探测：值 + 「为什么没有值」。调用方要读数时用 `getCPUTemperature()`；
    /// 支持报告要解释原因时用本方法。
    static func getCPUTemperatureProbe() -> TemperatureProbe {
        // Hold lock for entire read/compute/update, and touch only the cache internals
        // (`_cachedTemperature` / `_cacheTimestamp`) inside the block: NSLock is not reentrant.
        return temperatureLock.withLock {
            guard ensureConnection() else {
                let cached = readCachedTemperatureIfValid()
                let reason = cached == nil
                    ? TemperatureReason.connectionUnavailable
                    : TemperatureReason.usingCachedValue
                return unavailableTemperatureProbe(cached: cached, reason: reason)
            }

            let cpuTempKeys = Self.cpuTemperatureKeys
            var temperatures = readAcceptedTemperatures(keys: cpuTempKeys)

            if temperatures.isEmpty {
                // Possible stale connection (e.g. after sleep); reconnect and retry once.
                invalidateConnection()
                guard ensureConnection() else {
                    let cached = readCachedTemperatureIfValid()
                    let reason = cached == nil
                        ? TemperatureReason.reconnectFailed
                        : TemperatureReason.usingCachedAfterReconnectFailure
                    return unavailableTemperatureProbe(cached: cached, reason: reason)
                }
                temperatures = readAcceptedTemperatures(keys: cpuTempKeys)
                guard !temperatures.isEmpty else {
                    let cached = readCachedTemperatureIfValid()
                    let reason = cached == nil
                        ? TemperatureReason.noValidTemperatureKeys
                        : TemperatureReason.usingCachedAfterEmptyRead
                    Self.recordProbe(
                        operation: "cpuTemperature",
                        status: cached == nil ? .unavailable : .degraded,
                        reasonCode: reason,
                        fields: temperatureCandidateFields(cpuTempKeys)
                    )
                    return TemperatureProbe(
                        celsius: cached,
                        reasonCode: reason,
                        acceptedKeyCount: 0,
                        usedCachedValue: cached != nil
                    )
                }
            }

            let avgTemp = temperatures.reduce(0, +) / Double(temperatures.count)
            let smoothedTemp: Double
            if let cached = _cachedTemperature {
                smoothedTemp = avgTemp * 0.7 + cached * 0.3
            } else {
                smoothedTemp = avgTemp
            }

            _cachedTemperature = smoothedTemp
            _cacheTimestamp = Date()
            Self.recordProbe(
                operation: "cpuTemperature",
                status: .success,
                reasonCode: TemperatureReason.keysRead,
                fields: ["acceptedKeyCount": .privateValue(.integer(Int64(temperatures.count)))]
            )
            return TemperatureProbe(
                celsius: smoothedTemp,
                reasonCode: TemperatureReason.keysRead,
                acceptedKeyCount: temperatures.count,
                usedCachedValue: false
            )
        }
    }

    /// Apple Silicon SOC / CPU Package / 风扇区域温度候选键。
    private static let cpuTemperatureKeys = [
        "Te05",
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0Y", "Tp0b", "Tp0e",
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0E"
    ]

    /// 读一遍候选键，返回落在 5–115 °C 的有效温度。`LIGHT_STATS_SMC_DEBUG=1` 时顺手写下逐键日志。
    private static func readAcceptedTemperatures(keys: [String]) -> [Double] {
        var temperatures: [Double] = []
        guard smcDebugEnabled else {
            for key in keys {
                if let temp = readTemperature(key: key), temp > 5 && temp < 115 {
                    temperatures.append(temp)
                }
            }
            return temperatures
        }

        var debugLog = "[Temperature Debug] Starting...\n[Temperature Debug] SMC connection opened\n"
        for key in keys {
            let result = readTemperatureDebug(key: key)
            debugLog += result.log
            if let temp = result.temp, temp > 5 && temp < 115 {
                temperatures.append(temp)
                debugLog += "  -> ACCEPTED\n"
            } else {
                debugLog += "  -> REJECTED (out of range 5-115)\n"
            }
        }
        debugLog += "[Temperature Debug] Valid temperatures: \(temperatures)\n"
        debugLog += "[Temperature Debug] Count: \(temperatures.count)\n"
        writeDebugLog(debugLog)
        return temperatures
    }

    /// 走缓存（或彻底读不到）时的探测结果：值可能来自缓存，原因码要说清是哪种。
    private static func unavailableTemperatureProbe(cached: Double?, reason: String) -> TemperatureProbe {
        Self.recordProbe(
            operation: "cpuTemperature",
            status: cached == nil ? .unavailable : .degraded,
            reasonCode: reason
        )
        return TemperatureProbe(
            celsius: cached,
            reasonCode: reason,
            acceptedKeyCount: 0,
            usedCachedValue: cached != nil
        )
    }

    /// Call only while holding temperatureLock. Returns cache if not expired; otherwise nil.
    private static func readCachedTemperatureIfValid() -> Double? {
        if let timestamp = _cacheTimestamp,
           Date().timeIntervalSince(timestamp) <= maxCacheAge,
           let value = _cachedTemperature {
            return value
        }
        return nil
    }

    // MARK: - SMC Connection (persistent)

    /// Ensure a usable SMC connection exists, opening a new one if needed.
    /// This is the single entry point for all SMC reads — the connection stays
    /// open across calls so `IOServiceOpen` (and its auth dialog) fires once,
    /// not every sampling cycle.
    static func ensureConnection() -> Bool {
        connLock.lock()
        defer { connLock.unlock() }

        if conn != 0 { return true }

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )

        guard service != 0 else {
            return false
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)

        guard result == kIOReturnSuccess else {
            conn = 0
            return false
        }

        return true
    }

    /// Close and reset the connection. Call this when an IOKit call fails
    /// (stale handle after sleep/wake) so the next `ensureConnection()` will
    /// open a fresh one.
    static func invalidateConnection() {
        connLock.lock()
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
        connLock.unlock()
    }

    // MARK: - Read Helpers

    /// 带调试信息的温度读取
    private static func readTemperatureDebug(key: String) -> (temp: Double?, log: String) {
        var log = "[Key: \(key)] "

        guard key.count == 4 else {
            log += "Invalid key length\n"
            return (nil, log)
        }

        let keyCode = fourCharCode(key)

        // Step 1: Get key info
        var inputStruct = SMCParamStruct()
        var outputStruct = SMCParamStruct()

        inputStruct.key = keyCode
        inputStruct.data8 = kSMCGetKeyInfo

        var outputSize = MemoryLayout<SMCParamStruct>.size

        var result = IOConnectCallStructMethod(
            conn,
            2,
            &inputStruct,
            MemoryLayout<SMCParamStruct>.size,
            &outputStruct,
            &outputSize
        )

        guard result == kIOReturnSuccess else {
            log += "GetKeyInfo failed (IOConnect error: \(result))\n"
            return (nil, log)
        }

        guard outputStruct.result == 0 else {
            log += "GetKeyInfo failed (SMC result: \(outputStruct.result))\n"
            return (nil, log)
        }

        let dataSize = Int(outputStruct.keyInfo.dataSize)
        let dataType = outputStruct.keyInfo.dataType

        // 转换 dataType 为可读字符串
        let typeStr = String(format: "%c%c%c%c",
                             (dataType >> 24) & 0xFF,
                             (dataType >> 16) & 0xFF,
                             (dataType >> 8) & 0xFF,
                             dataType & 0xFF)

        log += "type='\(typeStr)' size=\(dataSize) "

        guard dataSize > 0 && dataSize <= 32 else {
            log += "Invalid dataSize\n"
            return (nil, log)
        }

        // Step 2: Read actual data
        inputStruct = SMCParamStruct()
        inputStruct.key = keyCode
        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.data8 = kSMCReadKey

        outputStruct = SMCParamStruct()
        outputSize = MemoryLayout<SMCParamStruct>.size

        result = IOConnectCallStructMethod(
            conn,
            2,
            &inputStruct,
            MemoryLayout<SMCParamStruct>.size,
            &outputStruct,
            &outputSize
        )

        guard result == kIOReturnSuccess, outputStruct.result == 0 else {
            log += "ReadKey failed\n"
            return (nil, log)
        }

        // Extract bytes
        var bytes = [UInt8]()
        withUnsafeBytes(of: outputStruct.bytes) { ptr in
            for i in 0..<dataSize {
                bytes.append(ptr[i])
            }
        }

        let hexStr = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        log += "bytes=[\(hexStr)] "

        // Parse temperature
        if let temp = parseTemperatureValue(bytes: bytes, typeStr: typeStr) {
            if temp > 25 && temp < 115 {
                log += "  -> ACCEPTED\n"
                return (temp, log)
            } else {
                log += "  -> REJECTED (out of range 25-115)\n"
                return (nil, log)
            }
        }

        log += "parsed=nil\n"

        return (nil, log)
    }

    private static func readTemperature(key: String) -> Double? {
        guard key.count == 4 else { return nil }

        let keyCode = fourCharCode(key)
        var inputStruct = SMCParamStruct()
        var outputStruct = SMCParamStruct()

        inputStruct.key = keyCode
        inputStruct.data8 = kSMCGetKeyInfo

        var outputSize = MemoryLayout<SMCParamStruct>.size
        var result = IOConnectCallStructMethod(
            conn,
            2,
            &inputStruct,
            MemoryLayout<SMCParamStruct>.size,
            &outputStruct,
            &outputSize
        )

        guard result == kIOReturnSuccess, outputStruct.result == 0 else {
            return nil
        }

        let dataSize = Int(outputStruct.keyInfo.dataSize)
        guard dataSize > 0 && dataSize <= 32 else { return nil }

        let dataType = outputStruct.keyInfo.dataType
        let typeStr = String(format: "%c%c%c%c",
                             (dataType >> 24) & 0xFF,
                             (dataType >> 16) & 0xFF,
                             (dataType >> 8) & 0xFF,
                             dataType & 0xFF)

        inputStruct = SMCParamStruct()
        inputStruct.key = keyCode
        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.data8 = kSMCReadKey

        outputStruct = SMCParamStruct()
        outputSize = MemoryLayout<SMCParamStruct>.size
        result = IOConnectCallStructMethod(
            conn,
            2,
            &inputStruct,
            MemoryLayout<SMCParamStruct>.size,
            &outputStruct,
            &outputSize
        )

        guard result == kIOReturnSuccess, outputStruct.result == 0 else {
            return nil
        }

        var bytes = [UInt8]()
        withUnsafeBytes(of: outputStruct.bytes) { ptr in
            for i in 0..<dataSize {
                bytes.append(ptr[i])
            }
        }

        return parseTemperatureValue(bytes: bytes, typeStr: typeStr)
    }

    /// 根据类型字符串解析温度
    private static func parseTemperatureValue(bytes: [UInt8], typeStr: String) -> Double? {
        guard bytes.count >= 2 else { return nil }

        let trimmedType = typeStr.trimmingCharacters(in: .whitespaces)

        switch trimmedType {
        case "sp78":
            let value = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(value) / 256.0

        case "sp87":
            let value = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(value) / 128.0

        case "sp96":
            let value = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(value) / 64.0

        case "flt":
            guard bytes.count >= 4 else { return nil }
            var floatValue: Float = 0
            withUnsafeMutableBytes(of: &floatValue) { dest in
                bytes.prefix(4).enumerated().forEach { dest[$0.offset] = $0.element }
            }
            return Double(floatValue)

        case "ui8":
            return Double(bytes[0])

        case "ui16":
            let value = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(value)

        default:
            // 默认尝试 sp78
            let value = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(value) / 256.0
        }
    }

    // MARK: - Core SMC Read

    /// 一次键读取的完整结果：`missing` = 键不存在，`failed` = 键在但读失败。
    static func readKeyProbe(_ key: String) -> (outcome: KeyReadOutcome, bytes: [UInt8]?) {
        guard key.count == 4 else { return (.missing, nil) }

        let keyCode = fourCharCode(key)

        // Step 1: Get key info to know the data size
        var inputStruct = SMCParamStruct()
        var outputStruct = SMCParamStruct()

        inputStruct.key = keyCode
        inputStruct.data8 = kSMCGetKeyInfo

        var outputSize = MemoryLayout<SMCParamStruct>.size

        var result = IOConnectCallStructMethod(
            conn,
            2,  // kSMCHandleYPCEvent
            &inputStruct,
            MemoryLayout<SMCParamStruct>.size,
            &outputStruct,
            &outputSize
        )

        guard result == kIOReturnSuccess, outputStruct.result == 0 else {
            return (.missing, nil)
        }

        let dataSize = Int(outputStruct.keyInfo.dataSize)
        guard dataSize > 0 && dataSize <= 32 else { return (.failed, nil) }

        // Step 2: Read the actual data
        inputStruct = SMCParamStruct()
        inputStruct.key = keyCode
        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.data8 = kSMCReadKey

        outputStruct = SMCParamStruct()
        outputSize = MemoryLayout<SMCParamStruct>.size

        result = IOConnectCallStructMethod(
            conn,
            2,  // kSMCHandleYPCEvent
            &inputStruct,
            MemoryLayout<SMCParamStruct>.size,
            &outputStruct,
            &outputSize
        )

        guard result == kIOReturnSuccess, outputStruct.result == 0 else {
            return (.failed, nil)
        }

        // Extract bytes from output
        var bytes = [UInt8]()
        withUnsafeBytes(of: outputStruct.bytes) { ptr in
            for i in 0..<dataSize {
                bytes.append(ptr[i])
            }
        }

        return (.value, bytes)
    }

    private static func fourCharCode(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        for char in str.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    // MARK: - SMC Structures (must match AppleSMC.kext exactly)

    private struct SMCVersion {
        var major: CChar = 0
        var minor: CChar = 0
        var build: CChar = 0
        var reserved: CChar = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0  // Required for correct struct size (80 bytes)
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        // swiftlint:disable:next large_tuple
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }
}
