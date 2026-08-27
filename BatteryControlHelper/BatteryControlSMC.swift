import Foundation
import IOKit
import os

private enum BatteryControlSMCError: LocalizedError {
    case serviceUnavailable
    case connectionFailed(IOReturn)
    case malformedKey(String)
    case keyUnavailable(String)
    case invalidData(String)
    case operationFailed(String, IOReturn, UInt8)

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "AppleSMC service is unavailable"
        case .connectionFailed(let result):
            return "AppleSMC connection failed: \(result)"
        case .malformedKey(let key):
            return "Invalid SMC key: \(key)"
        case .keyUnavailable(let key):
            return "SMC key is unavailable: \(key)"
        case .invalidData(let key):
            return "Invalid SMC data: \(key)"
        case .operationFailed(let key, let result, let smcResult):
            return "SMC operation failed for \(key): io=\(result), smc=\(smcResult)"
        }
    }
}

final class BatteryControlSMC {
    private struct KeyInfo {
        let size: Int
        let dataType: UInt32
    }

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

    private typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let readKeySelector: UInt8 = 5
    private static let writeKeySelector: UInt8 = 6
    private static let keyInfoSelector: UInt8 = 9

    private let log = Logger(subsystem: BatteryControlIPC.helperBundleIdentifier, category: "SMC")
    private var connection: io_connect_t = 0
    private var supportsLegacyPair = false
    private var supportsLegacySingle = false
    private(set) var backend: BatteryControlBackendCode = .unknown

    init() {
        openConnection()
        detectCapabilities()
    }

    deinit {
        closeConnection()
    }

    func enableLegacyCharging() throws {
        guard backend == .legacy else { throw BatteryControlSMCError.keyUnavailable("legacy") }
        if supportsLegacyPair {
            try write(key: "CH0B", bytes: [0])
            try write(key: "CH0C", bytes: [0])
        } else if supportsLegacySingle {
            try write(key: "CHTE", bytes: [0, 0, 0, 0])
        } else {
            throw BatteryControlSMCError.keyUnavailable("legacy")
        }
        try verifyLegacyCharging(enabled: true)
    }

    func disableLegacyCharging() throws {
        guard backend == .legacy else { throw BatteryControlSMCError.keyUnavailable("legacy") }
        if supportsLegacyPair {
            try write(key: "CH0B", bytes: [2])
            try write(key: "CH0C", bytes: [2])
        } else if supportsLegacySingle {
            try write(key: "CHTE", bytes: [1, 0, 0, 0])
        } else {
            throw BatteryControlSMCError.keyUnavailable("legacy")
        }
        try verifyLegacyCharging(enabled: false)
    }

    func isLegacyChargingEnabled() throws -> Bool {
        guard backend == .legacy else { throw BatteryControlSMCError.keyUnavailable("legacy") }
        if supportsLegacyPair {
            let first = try read(key: "CH0B")
            let second = try read(key: "CH0C")
            return first.first == 0 && second.first == 0
        }
        if supportsLegacySingle {
            return try read(key: "CHTE") == [0, 0, 0, 0]
        }
        throw BatteryControlSMCError.keyUnavailable("legacy")
    }

    func readFirmwareLimit() throws -> (active: Bool, lower: Int, upper: Int) {
        guard backend == .firmware else { throw BatteryControlSMCError.keyUnavailable("firmware") }
        let active = try read(key: "bfF0").first == 2
        let upper = try readLittleEndianUInt32(key: "bfD0")
        let lower = try readLittleEndianUInt32(key: "bfE0")
        return (active: active, lower: Int(lower), upper: Int(upper))
    }

    func setFirmwareLimit(lower: Int, upper: Int) throws {
        guard backend == .firmware else { throw BatteryControlSMCError.keyUnavailable("firmware") }
        guard BatteryControlLimits.isValid(upper: upper, lower: lower) else {
            throw BatteryControlSMCError.invalidData("firmware limits")
        }

        let current = try readFirmwareLimit()
        if current.active, current.lower == lower, current.upper == upper {
            return
        }
        try write(key: "bfF0", bytes: [0])
        try writeLittleEndianUInt32(key: "bfD0", value: UInt32(upper))
        try writeLittleEndianUInt32(key: "bfE0", value: UInt32(lower))
        try write(key: "bfF0", bytes: [2])
        let updated = try readFirmwareLimit()
        guard updated.active, updated.lower == lower, updated.upper == upper else {
            throw BatteryControlSMCError.invalidData("firmware limit verification")
        }
    }

    func disableFirmwareLimit() throws {
        guard backend == .firmware else { throw BatteryControlSMCError.keyUnavailable("firmware") }
        guard try read(key: "bfF0").first == 2 else { return }
        try write(key: "bfF0", bytes: [0])
        guard try read(key: "bfF0").first == 0 else {
            throw BatteryControlSMCError.invalidData("firmware limit reset verification")
        }
    }

    private func verifyLegacyCharging(enabled: Bool) throws {
        if supportsLegacyPair {
            let expected: UInt8 = enabled ? 0 : 2
            guard try read(key: "CH0B") == [expected],
                  try read(key: "CH0C") == [expected] else {
                throw BatteryControlSMCError.invalidData("legacy charging verification")
            }
            return
        }
        if supportsLegacySingle {
            let expected: [UInt8] = enabled ? [0, 0, 0, 0] : [1, 0, 0, 0]
            guard try read(key: "CHTE") == expected else {
                throw BatteryControlSMCError.invalidData("legacy charging verification")
            }
            return
        }
        throw BatteryControlSMCError.keyUnavailable("legacy")
    }

    private func openConnection() {
        guard connection == 0 else { return }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else {
            log.error("AppleSMC service unavailable")
            return
        }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard result == kIOReturnSuccess else {
            connection = 0
            log.error("AppleSMC connection failed: \(result)")
            return
        }
        log.info("AppleSMC connection opened")
    }

    private func closeConnection() {
        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }

    private func detectCapabilities() {
        let firmwareKeys = ["bfF0", "bfD0", "bfE0"]
        if firmwareKeys.allSatisfy({ hasKey($0) }) {
            backend = .firmware
            log.info("Detected firmware charge-control backend")
            return
        }

        supportsLegacyPair = hasKey("CH0B") && hasKey("CH0C")
        supportsLegacySingle = hasKey("CHTE")
        if supportsLegacyPair || supportsLegacySingle {
            backend = .legacy
            log.info("Detected legacy charge-control backend")
        } else {
            backend = .unknown
            log.info("No charge-control backend detected")
        }
    }

    private func hasKey(_ key: String) -> Bool {
        do {
            _ = try keyInformation(for: key)
            return true
        } catch {
            return false
        }
    }

    private func keyInformation(for key: String) throws -> KeyInfo {
        guard key.utf8.count == 4 else { throw BatteryControlSMCError.malformedKey(key) }
        guard connection != 0 else { throw BatteryControlSMCError.serviceUnavailable }
        var input = SMCParamStruct()
        input.key = fourCharacterCode(key)
        input.data8 = Self.keyInfoSelector
        let output = try call(&input, key: key)
        let size = Int(output.keyInfo.dataSize)
        guard size > 0, size <= 32 else { throw BatteryControlSMCError.invalidData(key) }
        return KeyInfo(size: size, dataType: output.keyInfo.dataType)
    }

    private func read(key: String) throws -> [UInt8] {
        let info = try keyInformation(for: key)
        var input = SMCParamStruct()
        input.key = fourCharacterCode(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.keyInfo.dataType = info.dataType
        input.data8 = Self.readKeySelector
        let output = try call(&input, key: key)
        return bytes(from: output.bytes, count: info.size)
    }

    private func write(key: String, bytes: [UInt8]) throws {
        let info = try keyInformation(for: key)
        guard bytes.count == info.size else {
            throw BatteryControlSMCError.invalidData(key)
        }
        var input = SMCParamStruct()
        input.key = fourCharacterCode(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.keyInfo.dataType = info.dataType
        input.data8 = Self.writeKeySelector
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (index, byte) in bytes.enumerated() {
                buffer[index] = byte
            }
        }
        _ = try call(&input, key: key)
    }

    private func readLittleEndianUInt32(key: String) throws -> UInt32 {
        let bytes = try read(key: key)
        guard let value = BatteryControlSMCEncoding.littleEndianUInt32(from: bytes) else {
            throw BatteryControlSMCError.invalidData(key)
        }
        return value
    }

    private func writeLittleEndianUInt32(key: String, value: UInt32) throws {
        try write(key: key, bytes: BatteryControlSMCEncoding.littleEndianBytes(from: value))
    }

    private func call(_ input: inout SMCParamStruct, key: String) throws -> SMCParamStruct {
        guard MemoryLayout<SMCParamStruct>.size == 80 else {
            throw BatteryControlSMCError.invalidData("SMCParamStruct")
        }
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.size
        let result = IOConnectCallStructMethod(
            connection,
            2,
            &input,
            MemoryLayout<SMCParamStruct>.size,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess, output.result == 0 else {
            throw BatteryControlSMCError.operationFailed(key, result, output.result)
        }
        return output
    }

    private func bytes(from tuple: SMCBytes, count: Int) -> [UInt8] {
        withUnsafeBytes(of: tuple) { Array($0.prefix(count)) }
    }

    private func fourCharacterCode(_ key: String) -> UInt32 {
        key.utf8.reduce(0) { partialResult, byte in
            (partialResult << 8) | UInt32(byte)
        }
    }
}
