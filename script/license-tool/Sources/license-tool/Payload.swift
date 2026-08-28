import Foundation

/// Signed payload embedded in every activation code.
///
/// Mirrors the JSON shape decoded by `Light Stats/Services/LicenseValidator.swift` —
/// keep both in sync. `v` is the payload version, `f` the granted feature keys,
/// `o` the owner name, `i` the issue time as Unix seconds. Lifetime codes carry no
/// expiry field.
struct PayloadJSON: Codable {
    var v: Int
    var f: [String]
    var o: String
    var i: Int64
}

enum Payload {
    static let version = 1

    static func build(features: [String], owner: String, issuedAt: Int64) -> Data? {
        let payload = PayloadJSON(v: version, f: features, o: owner, i: issuedAt)
        return try? JSONEncoder().encode(payload)
    }

    static func decode(_ data: Data) -> PayloadJSON? {
        try? JSONDecoder().decode(PayloadJSON.self, from: data)
    }
}
