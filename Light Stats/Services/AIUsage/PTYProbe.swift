//
//  PTYProbe.swift
//  Light Stats
//
//  Shared pseudo-terminal capture engine for the AI-usage CLI fallbacks.
//
//  Claude (`/usage`) and Codex (`/status`) both launch their CLI inside a PTY,
//  send a slash command, and scrape the TUI-rendered usage panel. The mechanics
//  — openpty, a non-blocking read loop, temp working directory, terminate/SIGKILL
//  teardown, ANSI stripping — are identical; only the per-CLI knobs (window size,
//  arguments, initial delay, command, completion predicate, and Codex's
//  "dismiss the update banner" interaction) differ. Those live in `Config`.
//
//  This is a best-effort scraper of undocumented TUIs: every failure maps to
//  `AIUsageError.network`, matching the previous per-provider behavior.
//

import Foundation

nonisolated enum PTYProbe {

    /// What the output handler wants the read loop to do next.
    enum Decision {
        /// Keep polling for more output.
        case keepReading
        /// Enough data captured — settle, do a final read, and return the text.
        case complete
        /// Discard everything captured so far and keep polling (used after an
        /// interaction re-renders the screen, e.g. dismissing an update banner).
        case reset
    }

    struct Config {
        var arguments: [String]
        var winsize: winsize
        /// How long to wait after launch before sending `command` (CLI warm-up).
        var initialDelay: TimeInterval
        /// Slash command sent once after `initialDelay` (e.g. "/usage\r\n").
        var command: String
        /// Delay between read polls.
        var pollInterval: TimeInterval
        /// After `.complete`, wait this long then do one final read (lets the TUI
        /// finish painting the panel).
        var settleDelay: TimeInterval
        /// Temp working-directory name prefix, so the CLI doesn't pick up a
        /// project config file (e.g. CLAUDE.md) from the real cwd.
        var workDirPrefix: String
        /// Invoked for each accumulated, ANSI-stripped chunk. May call `write`
        /// and `Thread.sleep` (it runs on the probe's background thread) — that
        /// is how Codex dismisses its update prompt before retrying `/status`.
        var onOutput: (_ cleanText: String, _ write: (String) -> Void) -> Decision
    }

    /// Launches `binary` in a PTY and captures its TUI output per `config`.
    /// Throws `AIUsageError.network` on any setup failure or timeout-without-data.
    static func capture(binary: String, timeout: TimeInterval, config: Config) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try captureSync(binary: binary, timeout: timeout, config: config))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Strips ANSI/CSI escape sequences (ESC [ … ending in 0x40–0x7E).
    static func stripANSICodes(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]") else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    // MARK: - Implementation

    private static func captureSync(binary: String, timeout: TimeInterval, config: Config) throws -> String {
        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var win = config.winsize

        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            throw AIUsageError.network
        }
        // Non-blocking primary so the read loop can poll.
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        defer {
            close(primaryFD)
            close(secondaryFD)
        }

        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: false)
        defer { try? secondaryHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = config.arguments
        process.standardInput = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError = secondaryHandle
        process.environment = CLIBinaryResolver.enrichedEnvironment()

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(config.workDirPrefix)\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        process.currentDirectoryURL = workDir

        guard (try? process.run()) != nil else {
            throw AIUsageError.network
        }
        defer {
            if process.isRunning {
                process.terminate()
                // Escalate to SIGKILL shortly after if it ignored SIGTERM.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }

        let write: (String) -> Void = { text in _ = try? writeAll(primaryFD, Data(text.utf8)) }

        // Wait for the CLI to initialize, then send the command.
        Thread.sleep(forTimeInterval: config.initialDelay)
        write(config.command)

        var allOutput = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var completed = false

        while Date() < deadline {
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = read(primaryFD, &buf, buf.count)
            if n > 0 {
                allOutput.append(contentsOf: buf.prefix(n))
                if let text = String(data: allOutput, encoding: .utf8) {
                    switch config.onOutput(stripANSICodes(text), write) {
                    case .keepReading:
                        break
                    case .reset:
                        allOutput.removeAll()
                    case .complete:
                        completed = true
                        Thread.sleep(forTimeInterval: config.settleDelay)
                        var finalBuf = [UInt8](repeating: 0, count: 8192)
                        let finalN = read(primaryFD, &finalBuf, finalBuf.count)
                        if finalN > 0 { allOutput.append(contentsOf: finalBuf.prefix(finalN)) }
                    }
                    if completed { break }
                }
            }
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: config.pollInterval)
        }

        guard completed,
              let text = String(data: allOutput, encoding: .utf8),
              !text.isEmpty else {
            throw AIUsageError.network
        }

        return text
    }

    /// Writes all of `data` to `fd`, retrying on EAGAIN/EWOULDBLOCK.
    private static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(fd, base.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        usleep(5000)
                        continue
                    }
                    throw AIUsageError.network
                }
                offset += written
            }
        }
    }
}
