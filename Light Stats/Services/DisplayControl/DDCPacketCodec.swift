//
//  DDCPacketCodec.swift
//  Light Stats
//

nonisolated enum DDCPacketCodec {
    struct Reply: Equatable, Sendable {
        let resultCode: UInt8
        let vcpCode: UInt8
        let maximum: UInt16
        let current: UInt16
    }

    private static let checksumAddress: UInt8 = 0x37
    private static let dataAddress: UInt8 = 0x51
    private static let replyChecksumSeed: UInt8 = 0x50

    static func readRequest(vcpCode: UInt8) -> [UInt8] {
        request(payload: [vcpCode])
    }

    static func writeRequest(vcpCode: UInt8, value: UInt16) -> [UInt8] {
        request(payload: [vcpCode, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    static func parseReply(_ bytes: [UInt8], expectedVCPCode: UInt8) -> Reply? {
        guard bytes.count >= 11,
              bytes[1] & 0x7F >= 8,
              bytes[2] == 0x02,
              bytes[4] == expectedVCPCode,
              hasValidReplyChecksum(bytes)
        else {
            return nil
        }

        return Reply(
            resultCode: bytes[3],
            vcpCode: bytes[4],
            maximum: UInt16(bytes[6]) << 8 | UInt16(bytes[7]),
            current: UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        )
    }

    static func checksum(seed: UInt8, bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(seed, ^)
    }

    private static func request(payload: [UInt8]) -> [UInt8] {
        var packet = [UInt8(0x80 | (payload.count + 1)), UInt8(payload.count)] + payload + [0]
        let seed = payload.count == 1
            ? checksumAddress << 1
            : checksumAddress << 1 ^ dataAddress
        packet[packet.count - 1] = checksum(seed: seed, bytes: packet.dropLast())
        return packet
    }

    private static func hasValidReplyChecksum(_ bytes: [UInt8]) -> Bool {
        guard let expected = bytes.last else { return false }
        return checksum(seed: replyChecksumSeed, bytes: bytes.dropLast()) == expected
    }
}
