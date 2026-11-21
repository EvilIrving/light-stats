//
//  CursorSafeStorage.swift
//  Light Stats
//

import CommonCrypto
import Foundation
import Security

/// Decrypts the session Cursor encrypts with Electron's safeStorage since 3.27.
///
/// The stored value is `cursor-safe-storage:v1:` followed by base64 of Chromium's
/// macOS ciphertext: the `v10` tag and AES-128-CBC, keyed by PBKDF2-HMAC-SHA1 over
/// the password Cursor keeps in the login keychain (generic password
/// `service = "Cursor Safe Storage"`, `account = "Cursor Key"`), salt `saltysalt`,
/// 1003 rounds, IV of sixteen spaces. Cursor's item owns the password; this type
/// only reads it, and only after the format says a key is actually needed.
nonisolated enum CursorSafeStorage {
    /// Any stored value with this prefix is ciphertext, whatever its version.
    /// A value without it is a plaintext token from a build before 3.27.
    static let prefix = "cursor-safe-storage:"

    static let keychainService = "Cursor Safe Storage"

    private static let versionPrefix = "cursor-safe-storage:v1:"
    private static let cipherPrefix = Data("v10".utf8)
    private static let salt = Data("saltysalt".utf8)
    private static let rounds: UInt32 = 1003
    private static let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
    /// Both bounds are far above any real value (a token is about 600 bytes), so a
    /// hostile row cannot make this decode or prompt for anything.
    private static let longestValue = 16 * 1024
    private static let longestPassword = 4 * 1024

    static func isEncrypted(_ stored: String) -> Bool {
        stored.hasPrefix(prefix)
    }

    /// The ciphertext of a stored value, or `nil` when this build cannot decrypt
    /// it: another version, broken base64, or a shape AES-CBC cannot have.
    static func ciphertext(of stored: String) -> Data? {
        guard stored.utf8.count <= longestValue,
              stored.hasPrefix(versionPrefix),
              let sealed = Data(base64Encoded: String(stored.dropFirst(versionPrefix.count))),
              sealed.starts(with: cipherPrefix) else {
            return nil
        }
        let body = sealed.dropFirst(cipherPrefix.count)
        guard !body.isEmpty, body.count.isMultiple(of: kCCBlockSizeAES128) else { return nil }
        return Data(body)
    }

    // MARK: - Keychain

    /// What reading the keychain produced.
    enum KeychainGrant: Equatable {
        /// Every password stored under Cursor's safeStorage service. More than one
        /// only if a build left an older item behind; each is tried in turn.
        case passwords([Data])
        /// The user refused the prompt.
        case denied
        /// No item, an unreadable item, or a locked keychain.
        case unavailable(OSStatus)
    }

    /// Reads the password Cursor's safeStorage is keyed with.
    ///
    /// Two steps, because the file-based keychain rejects `kSecMatchLimitAll`
    /// together with `kSecReturnData` (`errSecParam`): the accounts are enumerated by
    /// attribute, then each one's data is read on its own. The account name is
    /// deliberately not trusted — it is `Cursor Key` on 3.31.15, and the service is
    /// the coordinate that has held.
    ///
    /// The data read is the only call in the provider that can show a system dialog:
    /// the item belongs to Cursor, so macOS asks the first time Light Stats reads it
    /// and honors "Always Allow" from then on. It is interactive on purpose — a silent
    /// read cannot be granted, and the alternative (`/usr/bin/security`) would hand
    /// the same password to any process that can run it.
    static func keychainPasswords() -> KeychainGrant {
        let accounts: [String]
        switch accountNames() {
        case .found(let names): accounts = names
        case .denied: return .denied
        case .unavailable(let status): return .unavailable(status)
        }
        var passwords: [Data] = []
        var lastStatus = errSecItemNotFound
        for account in accounts {
            switch password(for: account) {
            case .passwords(let data): passwords.append(contentsOf: data)
            case .denied: return .denied
            case .unavailable(let status): lastStatus = status
            }
        }
        return passwords.isEmpty ? .unavailable(lastStatus) : .passwords(passwords)
    }

    private enum AccountList {
        case found([String])
        case denied
        case unavailable(OSStatus)
    }

    /// Reading attributes is not reading a secret, so this never prompts; the first
    /// data read does.
    private static func accountNames() -> AccountList {
        var result: CFTypeRef?
        switch SecItemCopyMatching(enumerationQuery() as CFDictionary, &result) {
        case errSecSuccess:
            let accounts = (result as? [[String: Any]] ?? []).compactMap {
                $0[kSecAttrAccount as String] as? String
            }
            return accounts.isEmpty ? .unavailable(errSecItemNotFound) : .found(accounts)
        case errSecItemNotFound:
            return .unavailable(errSecItemNotFound)
        case errSecUserCanceled, errSecAuthFailed:
            return .denied
        case let status:
            return .unavailable(status)
        }
    }

    private static func password(for account: String) -> KeychainGrant {
        var query = enumerationQuery()
        query[kSecAttrAccount] = account
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        query[kSecReturnAttributes] = nil

        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data,
                  !data.isEmpty,
                  data.count <= longestPassword else {
                return .unavailable(errSecParam)
            }
            return .passwords([data])
        case errSecItemNotFound:
            return .unavailable(errSecItemNotFound)
        case errSecUserCanceled, errSecAuthFailed:
            return .denied
        case let status:
            return .unavailable(status)
        }
    }

    private static func enumerationQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            // Cursor's item lives in the file-based login keychain. Without this the
            // search goes to the data protection keychain, where Chromium never wrote
            // it, and answers errSecItemNotFound.
            kSecUseDataProtectionKeychain: false
        ]
    }

    // MARK: - Decryption

    /// The access token, or `nil` when decryption fails or does not give a JWT.
    ///
    /// CBC is unauthenticated: a wrong password can still unpad into something, so
    /// the plaintext is checked before it is sent anywhere. The derived key and the
    /// plaintext buffer are wiped before returning; copies the crypto library makes
    /// are out of reach.
    static func accessToken(decrypting ciphertext: Data, password: Data) -> String? {
        guard var key = deriveKey(password) else { return nil }
        defer { key.resetBytes(in: 0..<key.count) }

        guard var plaintext = decrypt(ciphertext, key: key) else { return nil }
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }

        guard let token = String(data: plaintext, encoding: .utf8),
              looksLikeJWT(token) else {
            return nil
        }
        return token
    }

    private static func deriveKey(_ password: Data) -> Data? {
        guard !password.isEmpty, password.count <= longestPassword else { return nil }
        var key = Data(count: kCCKeySizeAES128)
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                key.withUnsafeMutableBytes { keyBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: CChar.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        rounds,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyBytes.count
                    )
                }
            }
        }
        return status == kCCSuccess ? key : nil
    }

    private static func decrypt(_ ciphertext: Data, key: Data) -> Data? {
        var plaintext = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var written = 0
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                ciphertext.withUnsafeBytes { ciphertextBytes in
                    plaintext.withUnsafeMutableBytes { plaintextBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyBytes.count,
                            ivBytes.baseAddress,
                            ciphertextBytes.baseAddress, ciphertextBytes.count,
                            plaintextBytes.baseAddress, plaintextBytes.count,
                            &written
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess, written > 0, written <= plaintext.count else { return nil }
        // A copy, so wiping the buffer below cannot reach the returned bytes.
        return Data(plaintext.prefix(written))
    }

    /// Three non-empty base64url parts, which is the shape of Cursor's access tokens.
    private static func looksLikeJWT(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return parts.count == 3 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(alphabet.contains)
        }
    }
}
