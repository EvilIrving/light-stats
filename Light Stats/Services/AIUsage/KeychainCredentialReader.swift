//
//  KeychainCredentialReader.swift
//  Light Stats
//
//  Reads Keychain secrets via the `/usr/bin/security` CLI rather than
//  `SecItemCopyMatching`. The CLI path does NOT raise the macOS authorization
//  dialog, so a monitoring app can read a CLI tool's stored credential silently
//  (the user already granted that tool access). Shared by the AI-usage services.
//

import Foundation
import os

nonisolated enum KeychainCredentialReader {

    private static let log = AppLogger(category: "Keychain")

    /// Reads a generic-password secret's raw blob for `service` via
    /// `security find-generic-password -s <service> -w`. Returns nil if the
    /// item is absent, the CLI fails to launch, or the value is empty.
    static func readGenericPassword(service: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            log.error("security CLI launch failed: \(error.localizedDescription)")
            return nil
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errText = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            log.notice("security CLI exit \(process.terminationStatus): \(errText)")
            return nil
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }
}
