//
//  CursorSafeStorageTests.swift
//  Light Stats Tests
//

import CommonCrypto
import XCTest
@testable import Light_Stats

/// The stored format, without Cursor and without the keychain: every test
/// encrypts a fictional token with a fictional password, using the same
/// parameters Chromium's macOS `v10` scheme uses.
final class CursorSafeStorageTests: XCTestCase {
    private static let password = Data("fictional-safe-storage-password".utf8)
    private static let token = "aaa.eyJzdWIiOiJhdXRoMHx1c2VyX2FiYyIsImV4cCI6NDEwMjQ0NDgwMH0.sig"

    func testDecryptsAVersionOneStoredValue() throws {
        let stored = try Self.stored(Self.token, password: Self.password)
        let ciphertext = try XCTUnwrap(CursorSafeStorage.ciphertext(of: stored))
        XCTAssertEqual(
            CursorSafeStorage.accessToken(decrypting: ciphertext, password: Self.password),
            Self.token
        )
    }

    func testWrongPasswordGivesNoToken() throws {
        let stored = try Self.stored(Self.token, password: Self.password)
        let ciphertext = try XCTUnwrap(CursorSafeStorage.ciphertext(of: stored))
        XCTAssertNil(CursorSafeStorage.accessToken(decrypting: ciphertext, password: Data("wrong".utf8)))
    }

    /// The other versions are not this format, and a plaintext token is not
    /// ciphertext: both must be refused before anything asks for a password.
    func testOnlyVersionOneCiphertextIsAccepted() throws {
        let stored = try Self.stored(Self.token, password: Self.password)
        let body = stored.dropFirst("cursor-safe-storage:v1:".count)
        XCTAssertNil(CursorSafeStorage.ciphertext(of: "cursor-safe-storage:v2:\(body)"))
        XCTAssertNil(CursorSafeStorage.ciphertext(of: Self.token))
        XCTAssertNil(CursorSafeStorage.ciphertext(of: "cursor-safe-storage:v1:not-base64"))
        XCTAssertTrue(CursorSafeStorage.isEncrypted(stored))
        XCTAssertFalse(CursorSafeStorage.isEncrypted(Self.token))
    }

    /// A decrypted value that is not a token is not sent anywhere: CBC is
    /// unauthenticated, so a wrong key can still unpad into something.
    func testDecryptedNonTokenIsRejected() throws {
        let stored = try Self.stored("not a jwt at all", password: Self.password)
        let ciphertext = try XCTUnwrap(CursorSafeStorage.ciphertext(of: stored))
        XCTAssertNil(CursorSafeStorage.accessToken(decrypting: ciphertext, password: Self.password))
    }

    private static func stored(_ token: String, password: Data) throws -> String {
        var key = Data(count: kCCKeySizeAES128)
        let salt = Data("saltysalt".utf8)
        let derived = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                key.withUnsafeMutableBytes { keyBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: CChar.self).baseAddress, password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress, keyBytes.count
                    )
                }
            }
        }
        XCTAssertEqual(derived, Int32(kCCSuccess))

        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        let plaintext = Data(token.utf8)
        var sealed = Data(count: plaintext.count + kCCBlockSizeAES128)
        var written = 0
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                plaintext.withUnsafeBytes { plaintextBytes in
                    sealed.withUnsafeMutableBytes { sealedBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyBytes.count, ivBytes.baseAddress,
                            plaintextBytes.baseAddress, plaintextBytes.count,
                            sealedBytes.baseAddress, sealedBytes.count, &written
                        )
                    }
                }
            }
        }
        XCTAssertEqual(status, CCCryptorStatus(kCCSuccess))
        var envelope = Data("v10".utf8)
        envelope.append(sealed.prefix(written))
        return "cursor-safe-storage:v1:\(envelope.base64EncodedString())"
    }
}
