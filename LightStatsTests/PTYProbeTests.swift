//
//  PTYProbeTests.swift
//  Light Stats Tests
//
//  Deterministic coverage for the shared PTY capture engine. Drives `PTYProbe`
//  with a synthetic shell script (no claude/codex CLI required) so the read-loop
//  / completion-predicate / timeout / buffer-reset / ANSI-stripping logic has a
//  regression net — the live CLI paths can't run in CI.
//

import XCTest
@testable import Light_Stats

final class PTYProbeTests: XCTestCase {

    private var scripts: [URL] = []

    override func tearDown() {
        for url in scripts { try? FileManager.default.removeItem(at: url) }
        scripts.removeAll()
        super.tearDown()
    }

    /// Writes an executable `/bin/sh` script and returns its path.
    private func makeScript(_ body: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptyprobe-\(UUID().uuidString.prefix(8)).sh")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        scripts.append(url)
        return url.path
    }

    private func config(
        initialDelay: TimeInterval = 0.1,
        pollInterval: TimeInterval = 0.05,
        settleDelay: TimeInterval = 0.1,
        onOutput: @escaping (String, (String) -> Void) -> PTYProbe.Decision
    ) -> PTYProbe.Config {
        PTYProbe.Config(
            arguments: [],
            winsize: winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0),
            initialDelay: initialDelay,
            command: "",
            pollInterval: pollInterval,
            settleDelay: settleDelay,
            workDirPrefix: "ptyprobe-test-",
            onOutput: onOutput
        )
    }

    // MARK: - stripANSICodes (pure)

    func testStripANSICodes() {
        XCTAssertEqual(PTYProbe.stripANSICodes("a\u{1B}[31mb\u{1B}[0mc"), "abc")
        XCTAssertEqual(PTYProbe.stripANSICodes("plain"), "plain")
    }

    // MARK: - capture

    func testCaptureCompletesAtPredicate() async throws {
        let script = try makeScript("printf 'hello world\\nDONE_MARKER 42%%\\n'; sleep 5")
        let text = try await PTYProbe.capture(
            binary: script,
            timeout: 4,
            config: config { clean, _ in
                clean.contains("DONE_MARKER") ? .complete : .keepReading
            }
        )
        XCTAssertTrue(text.contains("DONE_MARKER"))
        XCTAssertTrue(text.contains("hello world"))
    }

    func testPredicateReceivesANSIStrippedText() async throws {
        // Split the marker with an ANSI sequence: the predicate only matches if
        // the engine stripped it before calling onOutput.
        let script = try makeScript("printf 'DO\\033[31mNE_NOW\\033[0m\\n'; sleep 5")
        let text = try await PTYProbe.capture(
            binary: script,
            timeout: 4,
            config: config { clean, _ in
                clean.contains("DONE_NOW") ? .complete : .keepReading
            }
        )
        XCTAssertTrue(text.contains("NE_NOW"))
    }

    func testTimeoutWithoutCompletionThrowsNetwork() async {
        let script = try? makeScript("printf 'just noise\\n'; sleep 5")
        guard let script else { return XCTFail("script setup failed") }
        do {
            _ = try await PTYProbe.capture(
                binary: script,
                timeout: 1,
                config: config { _, _ in .keepReading }   // never completes
            )
            XCTFail("expected a timeout throw")
        } catch {
            XCTAssertEqual(error as? AIUsageError, .network)
        }
    }

    func testResetDiscardsEarlierOutput() async throws {
        // Print a banner, pause, then the real payload. onOutput resets on the
        // banner (clearing the buffer) and completes on the payload — so the
        // returned text must contain the payload but not the banner.
        let script = try makeScript("printf 'BANNER_LINE\\n'; sleep 0.5; printf 'PAYLOAD 7%%\\n'; sleep 5")
        var didReset = false
        let text = try await PTYProbe.capture(
            binary: script,
            timeout: 5,
            config: config(pollInterval: 0.04) { clean, _ in
                if clean.contains("PAYLOAD") { return .complete }
                if clean.contains("BANNER_LINE") { didReset = true; return .reset }
                return .keepReading
            }
        )
        XCTAssertTrue(didReset, "banner should have triggered a reset")
        XCTAssertTrue(text.contains("PAYLOAD"))
        XCTAssertFalse(text.contains("BANNER_LINE"), "reset should have discarded the banner")
    }
}
