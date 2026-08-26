import Foundation

enum BatteryControlSMCEncoding {
    static func littleEndianBytes(from value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ]
    }

    static func littleEndianUInt32(from bytes: [UInt8]) -> UInt32? {
        guard bytes.count == 4 else { return nil }
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }
}
