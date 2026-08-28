import Foundation

/// Wire codec for offline activation codes.
///
/// Mirrors `Light Stats/Services/LicenseCodec.swift` — keep both files in sync.
/// The golden fixture in `LightStatsTests/LicenseValidatorTests` pins the wire
/// format on the app side; run `swift test` here plus the app suite to catch drift.
enum LicenseCodec {
    static let prefix = "LS1"
    static let signatureLength = 64
    static let lengthFieldSize = 2

    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// `LS1-XXXXX-XXXXX-...` over base32(2-byte length || payload || signature).
    static func encode(payload: Data, signature: Data) -> String {
        var blob = Data(capacity: lengthFieldSize + payload.count + signature.count)
        let length = UInt16(payload.count)
        blob.append(UInt8(length >> 8))
        blob.append(UInt8(length & 0xFF))
        blob.append(payload)
        blob.append(signature)
        return prefix + "-" + group(base32Encode(blob))
    }

    static func decode(_ code: String) -> (payload: Data, signature: Data)? {
        let normalized = normalize(code)
        guard normalized.hasPrefix(prefix) else { return nil }
        let base32 = String(normalized.dropFirst(prefix.count))
        guard let blob = base32Decode(base32), blob.count >= lengthFieldSize + signatureLength else { return nil }
        let bytes = [UInt8](blob)
        let length = (Int(bytes[0]) << 8) | Int(bytes[1])
        let expectedLength = lengthFieldSize + length + signatureLength
        guard length > 0, expectedLength == bytes.count else { return nil }
        let payload = blob.subdata(in: lengthFieldSize..<(lengthFieldSize + length))
        let signatureStart = lengthFieldSize + length
        let signature = blob.subdata(in: signatureStart..<(signatureStart + signatureLength))
        return (payload, signature)
    }

    /// Input hygiene: strip separators and whitespace, uppercase.
    static func normalize(_ code: String) -> String {
        code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    static func group(_ string: String) -> String {
        var result = ""
        for (index, character) in string.enumerated() {
            if index > 0 && index % 5 == 0 { result.append("-") }
            result.append(character)
        }
        return result
    }

    static func base32Encode(_ data: Data) -> String {
        var result = ""
        var buffer: UInt32 = 0
        var bitsLeft = 0
        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                let index = Int((buffer >> UInt32(bitsLeft - 5)) & 0x1F)
                result.append(alphabet[index])
                bitsLeft -= 5
            }
        }
        if bitsLeft > 0 {
            let index = Int((buffer << UInt32(5 - bitsLeft)) & 0x1F)
            result.append(alphabet[index])
        }
        return result
    }

    static func base32Decode(_ string: String) -> Data? {
        var result = Data()
        var buffer: UInt32 = 0
        var bitsLeft = 0
        for character in string.uppercased() {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | UInt32(value)
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                result.append(UInt8((buffer >> UInt32(bitsLeft)) & 0xFF))
            }
        }
        if bitsLeft > 0 {
            let mask = (1 << bitsLeft) - 1
            guard buffer & UInt32(mask) == 0 else { return nil }
        }
        return result
    }
}
