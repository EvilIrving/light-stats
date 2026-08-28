//
//  LicenseValidatorTests.swift
//  Light Stats Tests
//
//  Pins the offline activation-code wire format and validation rules.
//

import CryptoKit
import XCTest
@testable import Light_Stats

final class LicenseValidatorTests: XCTestCase {

    /// Test-only keypair + code generated once by `script/license-tool`:
    ///   swift run license-tool generate-keypair --dir /tmp/light-stats-test-keys
    ///   swift run license-tool issue --private-key /tmp/light-stats-test-keys/private.key --owner "Fixture Owner"
    /// The fixture freezes the wire format: if `LicenseCodec` / `LicenseValidator` drift
    /// from the CLI tool, this code stops validating.
    private static let fixturePublicKeyBase64 = "ZXgf0P33ZXnIXGEQNSU4QANn0BjCM9SKwk9W6btFn/4="
    private static let fixtureCode = "LS1-AA6HW-ITGEI-5FWIT-GNFXG-ITLPO-VZWKI-S5FQR-HMIR2-GEWCE-2JCHI-YTOOB-XHEYD-COBZG-IWCE3-ZCHIR-EM2LY-OR2XE-ZJAJ5-3W4ZL-SEJ6V-A6BR5-G5ERC-MHOXY-AVS3H-4GUNF-LRXGZ-D3VCX-XD3P3-NPD5O-XTHNY-ATA2G-ME4V2-L3BTC-3KCPU-OLNOH-N5LOS-WKI5J-ANSBM-F6UYN-SX5ZV-AI"
    private static let fixtureOwner = "Fixture Owner"

    private struct PayloadJSON: Codable {
        let v: Int
        let f: [String]
        let o: String
        let i: Int64
    }

    private func fixturePublicKey() -> Curve25519.Signing.PublicKey? {
        guard let data = Data(base64Encoded: Self.fixturePublicKeyBase64) else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: data)
    }

    private func makeCode(features: [String], owner: String, version: Int = 1,
                          key: Curve25519.Signing.PrivateKey) throws -> String {
        let json = PayloadJSON(v: version, f: features, o: owner, i: 1_700_000_000)
        let payload = try JSONEncoder().encode(json)
        let signature = try key.signature(for: payload)
        return LicenseCodec.encode(payload: payload, signature: signature)
    }

    // MARK: - Golden fixture

    func testGoldenFixtureValidates() throws {
        let key = try XCTUnwrap(fixturePublicKey())
        let payload = LicenseValidator.validate(code: Self.fixtureCode, publicKey: key)
        XCTAssertEqual(payload?.owner, Self.fixtureOwner)
        XCTAssertEqual(payload?.features, [.findMouse])
        XCTAssertGreaterThan(payload?.issuedAt.timeIntervalSince1970 ?? 0, 1_700_000_000)
    }

    func testGoldenFixtureValidatesWithMessyInput() throws {
        let key = try XCTUnwrap(fixturePublicKey())
        let messy = Self.fixtureCode.lowercased().replacingOccurrences(of: "-", with: " ")
        XCTAssertNotNil(LicenseValidator.validate(code: messy, publicKey: key))
    }

    // MARK: - Round trip

    func testRoundTripWithInjectedKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let code = try makeCode(features: ["findMouse"], owner: "Tester", key: key)
        let payload = LicenseValidator.validate(code: code, publicKey: key.publicKey)
        XCTAssertEqual(payload?.owner, "Tester")
        XCTAssertEqual(payload?.features, [.findMouse])
    }

    // MARK: - Rejections

    func testRejectsTamperedCode() throws {
        let key = Curve25519.Signing.PrivateKey()
        let code = try makeCode(features: ["findMouse"], owner: "Tester", key: key)
        let flipped = String(code.prefix(code.count - 2)) + (code.last == "A" ? "B" : "A")
        XCTAssertNil(LicenseValidator.validate(code: flipped, publicKey: key.publicKey))
    }

    func testRejectsWrongKey() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let otherKey = Curve25519.Signing.PrivateKey()
        let code = try makeCode(features: ["findMouse"], owner: "Tester", key: signingKey)
        XCTAssertNil(LicenseValidator.validate(code: code, publicKey: otherKey.publicKey))
    }

    func testRejectsMalformedEncodings() throws {
        let key = Curve25519.Signing.PrivateKey()
        let code = try makeCode(features: ["findMouse"], owner: "Tester", key: key)
        XCTAssertNil(LicenseValidator.validate(code: "XX1-" + String(code.dropFirst(3)), publicKey: key.publicKey))
        XCTAssertNil(LicenseValidator.validate(code: "LS1-ZZZZ", publicKey: key.publicKey))
        XCTAssertNil(LicenseValidator.validate(code: String(code.prefix(20)), publicKey: key.publicKey))
        XCTAssertNil(LicenseValidator.validate(code: code + "-AAAAAAAA", publicKey: key.publicKey))
        XCTAssertNil(LicenseValidator.validate(code: "", publicKey: key.publicKey))
    }

    func testRejectsFuturePayloadVersion() throws {
        let key = Curve25519.Signing.PrivateKey()
        let code = try makeCode(features: ["findMouse"], owner: "Tester", version: 2, key: key)
        XCTAssertNil(LicenseValidator.validate(code: code, publicKey: key.publicKey))
    }

    // MARK: - Feature tolerance

    func testToleratesUnknownFeatureKeys() throws {
        let key = Curve25519.Signing.PrivateKey()
        let code = try makeCode(features: ["findMouse", "futureThing"], owner: "Tester", key: key)
        let payload = LicenseValidator.validate(code: code, publicKey: key.publicKey)
        XCTAssertEqual(payload?.features, [.findMouse])
    }

    func testAcceptsCodeGrantingNothing() throws {
        let key = Curve25519.Signing.PrivateKey()
        let code = try makeCode(features: [], owner: "Tester", key: key)
        XCTAssertEqual(LicenseValidator.validate(code: code, publicKey: key.publicKey)?.features, [])
    }

    // MARK: - Codec normalization

    func testNormalizeStripsSeparators() {
        XCTAssertEqual(LicenseCodec.normalize(" ls1-aaaa-bbbb "), "LS1AAAABBBB")
        XCTAssertEqual(LicenseCodec.normalize("LS1-AAAA-BBBB"), "LS1AAAABBBB")
    }
}
