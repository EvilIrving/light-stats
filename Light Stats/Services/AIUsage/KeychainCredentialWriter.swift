//
//  KeychainCredentialWriter.swift
//  Light Stats
//
//  Writes generic passwords via `/usr/bin/security -i` so the secret never
//  appears in process arguments. `SecItemAdd` / `SecItemCopyMatching` are
//  forbidden (they prompt).
//

import Foundation
import os

nonisolated enum KeychainCredentialWriter {

    static let service = "cain.com.light-stats.ai-usage"

    private static let log = AppLogger(category: "Keychain")

    enum WriteError: Error, Equatable {
        case emptySecret
        case controlCharacters
    }

    static func account(for id: AIProvider) -> String {
        "ai-usage.\(id.rawValue).token"
    }

    static func loadToken(for id: AIProvider) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try readToken(for: id)
        }.value
    }

    static func readToken(for id: AIProvider) throws -> String {
        guard let data = KeychainCredentialReader.readGenericPassword(
            service: service,
            account: account(for: id)
        ),
        let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
        !token.isEmpty else {
            throw AIUsageError.credentialsMissing
        }
        return token
    }

    /// `security -i` command line. Secret is POSIX single-quoted.
    static func addGenericPasswordCommand(account: String, secret: String) throws -> String {
        guard !secret.isEmpty else { throw WriteError.emptySecret }
        if secret.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            throw WriteError.controlCharacters
        }
        return [
            "add-generic-password",
            "-s", posixSingleQuoted(service),
            "-a", posixSingleQuoted(account),
            "-U",
            "-w", posixSingleQuoted(secret)
        ].joined(separator: " ")
    }

    static func posixSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func write(account: String, secret: String) -> Bool {
        let command: String
        do {
            command = try addGenericPasswordCommand(account: account, secret: secret)
        } catch {
            log.notice("keychain write rejected: \(String(describing: error))")
            return false
        }
        return runSecurity(arguments: ["-i"], stdin: command + "\n")
    }

    static func delete(account: String) -> Bool {
        runSecurity(
            arguments: ["delete-generic-password", "-s", service, "-a", account],
            stdin: nil
        )
    }

    private static func runSecurity(arguments: [String], stdin: String?) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let stdin {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? stdinPipe.fileHandleForWriting.close()
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        do {
            try process.run()
        } catch {
            log.error("security CLI launch failed: \(error.localizedDescription)")
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
