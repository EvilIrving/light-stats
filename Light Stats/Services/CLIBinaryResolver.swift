//
//  CLIBinaryResolver.swift
//  Light Stats
//
//  Created on 2026/06/18.
//

import Foundation

enum CLIBinaryResolver {

    private static let cacheLock = NSLock()
    private static var cachedLoginPath: [String]?
    private static var didCaptureLoginPath = false

    static func resolveClaudeBinary() -> String? {
        resolveBinary(
            name: "claude",
            overrideKey: "CLAUDE_CLI_PATH",
            wellKnownPaths: claudeWellKnownPaths()
        )
    }

    static func resolveCodexBinary() -> String? {
        resolveBinary(
            name: "codex",
            overrideKey: "CODEX_CLI_PATH",
            wellKnownPaths: codexWellKnownPaths()
        )
    }

    static func enrichedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = effectivePath().joined(separator: ":")
        return environment
    }

    private static func resolveBinary(
        name: String,
        overrideKey: String,
        wellKnownPaths: [String]
    ) -> String? {
        let environment = ProcessInfo.processInfo.environment
        let fm = FileManager.default

        if let override = environment[overrideKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           fm.isExecutableFile(atPath: override) {
            return override
        }

        if let pathHit = find(name, in: effectivePath(), fileManager: fm) {
            return pathHit
        }

        for candidate in wellKnownPaths where fm.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return commandFromLoginShell(name, fileManager: fm)
    }

    private static func effectivePath() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        var parts: [String] = []

        if let loginPath = loginShellPath() {
            parts.append(contentsOf: loginPath)
        }
        if let path = environment["PATH"] {
            parts.append(contentsOf: path.split(separator: ":").map(String.init))
        }

        parts.append(contentsOf: commonPathComponents())

        var seen = Set<String>()
        return parts.compactMap { raw in
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return path
        }
    }

    private static func commonPathComponents() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/pnpm/bin",
            "\(home)/Library/pnpm",
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "\(home)/.claude/bin",
            "\(home)/.npm-global/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
    }

    private static func claudeWellKnownPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.claude/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/Applications/cmux.app/Contents/Resources/bin/claude",
        ]
    }

    private static func codexWellKnownPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/pnpm/bin/codex",
            "\(home)/Library/pnpm/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
    }

    private static func loginShellPath() -> [String]? {
        cacheLock.lock()
        if didCaptureLoginPath {
            let value = cachedLoginPath
            cacheLock.unlock()
            return value
        }
        cacheLock.unlock()

        let marker = "__LIGHTSTATS_PATH__"
        let command = "printf '\(marker)%s\(marker)' \"$PATH\""
        let output = runLoginShell(command: command, timeout: 4)
        let value = output.flatMap { extractMarkedValue($0, marker: marker) }?
            .split(separator: ":")
            .map(String.init)

        cacheLock.lock()
        cachedLoginPath = value
        didCaptureLoginPath = true
        cacheLock.unlock()
        return value
    }

    private static func commandFromLoginShell(_ name: String, fileManager: FileManager) -> String? {
        guard let output = runLoginShell(command: "command -v \(name)", timeout: 2) else {
            return nil
        }

        for line in output.components(separatedBy: .newlines).reversed() {
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.hasPrefix("/"),
               URL(fileURLWithPath: path).lastPathComponent == name,
               fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func find(_ binary: String, in paths: [String], fileManager: FileManager) -> String? {
        for path in paths {
            let base = path.hasSuffix("/") ? String(path.dropLast()) : path
            let candidate = "\(base)/\(binary)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func extractMarkedValue(_ output: String, marker: String) -> String? {
        guard let start = output.range(of: marker),
              let end = output.range(of: marker, options: .backwards),
              start.upperBound <= end.lowerBound else {
            return nil
        }
        return String(output[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runLoginShell(command: String, timeout: TimeInterval) -> String? {
        let process = Process()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        let shellPath = shell.isEmpty ? "/bin/zsh" : shell
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l", "-i", "-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        guard (try? process.run()) != nil else { return nil }
        if finished.wait(timeout: .now() + timeout) != .success {
            process.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
