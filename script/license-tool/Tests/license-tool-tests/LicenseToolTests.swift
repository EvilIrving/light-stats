import CryptoKit
import XCTest
@testable import license_tool

final class LicenseToolTests: XCTestCase {

    func testIssueVerifyRoundtrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let payload = try XCTUnwrap(
            Payload.build(features: ["findMouse"], owner: "Tester", issuedAt: 1_700_000_000)
        )
        let signature = try key.signature(for: payload)
        let code = LicenseCodec.encode(payload: payload, signature: signature)

        XCTAssertTrue(code.hasPrefix("LS1-"))
        XCTAssertTrue(code.contains("-"))

        let decoded = try XCTUnwrap(LicenseCodec.decode(code))
        XCTAssertTrue(key.publicKey.isValidSignature(decoded.signature, for: decoded.payload))

        let json = try XCTUnwrap(Payload.decode(decoded.payload))
        XCTAssertEqual(json.o, "Tester")
        XCTAssertEqual(json.f, ["findMouse"])
        XCTAssertEqual(json.v, 1)
    }

    func testDecodeRejectsTamperedCode() throws {
        let key = Curve25519.Signing.PrivateKey()
        let payload = try XCTUnwrap(Payload.build(features: ["findMouse"], owner: "Tester", issuedAt: 1_700_000_000))
        let signature = try key.signature(for: payload)
        let code = LicenseCodec.encode(payload: payload, signature: signature)

        // Flip one base32 character so the signature can no longer match.
        let flipped = String(code.prefix(code.count - 2)) + (code.last == "A" ? "B" : "A")
        XCTAssertNil(LicenseCodec.decode(flipped).flatMap { decoded in
            key.publicKey.isValidSignature(decoded.signature, for: decoded.payload) ? decoded : nil
        })

        XCTAssertNil(LicenseCodec.decode("XX1-" + String(code.dropFirst(3))))
        XCTAssertNil(LicenseCodec.decode("LS1-ZZZZ"))
        XCTAssertNil(LicenseCodec.decode(code + "-AAAAAAAA"))
    }

    func testNormalizeInput() throws {
        let key = Curve25519.Signing.PrivateKey()
        let payload = try XCTUnwrap(Payload.build(features: ["findMouse"], owner: "Tester", issuedAt: 1_700_000_000))
        let signature = try key.signature(for: payload)
        let code = LicenseCodec.encode(payload: payload, signature: signature)

        let messy = code.lowercased().replacingOccurrences(of: "-", with: " ")
        let decoded = try XCTUnwrap(LicenseCodec.decode(messy))
        XCTAssertTrue(key.publicKey.isValidSignature(decoded.signature, for: decoded.payload))
    }
}
