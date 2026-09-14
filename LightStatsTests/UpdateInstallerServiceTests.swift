import XCTest
@testable import Light_Stats

final class UpdateInstallerServiceTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots {
            try FileManager.default.removeItem(at: root)
        }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testReplacesBundleWithSpacesAndShellMetacharactersInPaths() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(try run(fixture), 0)
        XCTAssertEqual(try text(fixture.result), "installed\n")
        XCTAssertEqual(try payload(fixture.destination), "new")
        XCTAssertEqual(try payload(fixture.source), "new")
        let backup = try XCTUnwrap(backups(fixture).first)
        XCTAssertEqual(try payload(backup), "old")
        XCTAssertEqual(backup.deletingLastPathComponent(), fixture.destination.deletingLastPathComponent())
        XCTAssertTrue(backup.lastPathComponent.hasPrefix(".LightStatsUpdate."))
        XCTAssertEqual(try text(fixture.backupRecord), "\(backup.path)\n")
        XCTAssertEqual(try text(fixture.root.appendingPathComponent("backup-at-first-rename")), "\(backup.path)\n")
        XCTAssertEqual(try text(fixture.openLog), "installed|new|\(fixture.destination.path)\n")
    }

    func testRepeatedInstallUsesDistinctBackups() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(try run(fixture), 0)
        let firstBackup = try XCTUnwrap(backups(fixture).first)
        XCTAssertEqual(try run(fixture), 0)
        XCTAssertEqual(try backups(fixture).count, 2)
        let secondBackup = try XCTUnwrap(backups(fixture).first { $0 != firstBackup })
        XCTAssertEqual(try text(fixture.backupRecord), "\(secondBackup.path)\n")
        XCTAssertEqual(try payload(firstBackup), "old")
        XCTAssertEqual(try payload(fixture.destination), "new")
    }

    func testBackupRecordFailureAbortsBeforeMovingOldBundle() throws {
        let fixture = try makeFixture()
        try FileManager.default.createDirectory(at: fixture.backupRecord, withIntermediateDirectories: false)
        XCTAssertEqual(try run(fixture), 1)
        try assertOldReopened(fixture, reason: "backup-write-failed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("move-count").path))
        XCTAssertTrue(try backups(fixture).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.backupRecord.path).isEmpty)
    }

    func testPartialCopyFailurePreservesAndReopensOldBundle() throws {
        let fixture = try makeFixture()
        let copy = try command("failed copy", in: fixture.root, body: #"""
        printf 'partial' > "$2/partial"
        exit 1
        """#)
        XCTAssertEqual(try run(fixture, copy: copy.path), 1)
        try assertOldReopened(fixture, reason: "copy-failed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupRecord.path))
        XCTAssertTrue(try backups(fixture).isEmpty)
        XCTAssertEqual(try payload(fixture.source), "new")
    }

    func testMissingSourcePreservesOldBundle() throws {
        let fixture = try makeFixture()
        try FileManager.default.removeItem(at: fixture.source)
        XCTAssertEqual(try run(fixture), 1)
        try assertOldReopened(fixture, reason: "copy-failed")
    }

    func testFirstRenameFailurePreservesOldBundle() throws {
        let fixture = try makeFixture(failedMoves: "1")
        XCTAssertEqual(try run(fixture), 1)
        try assertOldReopened(fixture, reason: "replace-failed")
        XCTAssertTrue(try backups(fixture).isEmpty)
    }

    func testSecondRenameFailureRestoresOldBundle() throws {
        let fixture = try makeFixture(failedMoves: "2")
        XCTAssertEqual(try run(fixture), 1)
        try assertOldReopened(fixture, reason: "replace-failed")
        XCTAssertEqual(try text(fixture.root.appendingPathComponent("move-count")), "3\n")
        XCTAssertEqual(try text(fixture.backupRecord), try text(fixture.root.appendingPathComponent("backup-at-first-rename")))
        XCTAssertTrue(try backups(fixture).isEmpty)
    }

    func testFailedRollbackKeepsAndOpensBackup() throws {
        let fixture = try makeFixture(failedMoves: "2,3")
        XCTAssertEqual(try run(fixture), 1)
        XCTAssertEqual(try text(fixture.result), "rollback-failed\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path))
        let backup = try XCTUnwrap(backups(fixture).first)
        XCTAssertEqual(try payload(backup), "old")
        XCTAssertEqual(try text(fixture.backupRecord), "\(backup.path)\n")
        XCTAssertEqual(try text(fixture.openLog), "rollback-failed|old|\(backup.path)\n")
    }

    func testNewAppOpenFailureRollsBackAndPublishesFailureBeforeOpeningOldApp() throws {
        let fixture = try makeFixture()
        try "".write(to: fixture.root.appendingPathComponent("fail-new-open"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try run(fixture), 1)
        XCTAssertEqual(try payload(fixture.destination), "old")
        XCTAssertEqual(try text(fixture.result), "relaunch-failed\n")
        XCTAssertEqual(
            try text(fixture.openLog),
            "installed|new|\(fixture.destination.path)\nrelaunch-failed|old|\(fixture.destination.path)\n"
        )
    }

    func testFailedNewBundleDisplacementKeepsBothBundlesAndOpensBackup() throws {
        let fixture = try makeFixture(failedMoves: "3")
        try "".write(to: fixture.root.appendingPathComponent("fail-new-open"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try run(fixture), 1)
        XCTAssertEqual(try payload(fixture.destination), "new")
        try assertBackupReopened(fixture)
    }

    func testFailedRestoreAfterOpenFailureKeepsBackupAndNewBundle() throws {
        let fixture = try makeFixture(failedMoves: "4")
        try "".write(to: fixture.root.appendingPathComponent("fail-new-open"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try run(fixture), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path))
        try assertBackupReopened(fixture)
        let siblings = try FileManager.default.contentsOfDirectory(at: fixture.root, includingPropertiesForKeys: nil)
        let retainedNew = try XCTUnwrap(siblings.first {
            $0.lastPathComponent.hasPrefix(".LightStatsUpdate.") && $0.pathExtension != "app"
        })
        XCTAssertEqual(try payload(retainedNew), "new")
    }

    func testRecoveryOpenFailureStillLeavesResultAndOldBundle() throws {
        let fixture = try makeFixture()
        try "".write(to: fixture.root.appendingPathComponent("fail-all-open"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try run(fixture, copy: "/usr/bin/false"), 1)
        XCTAssertEqual(try text(fixture.result), "relaunch-failed\n")
        XCTAssertEqual(try payload(fixture.destination), "old")
        XCTAssertEqual(try text(fixture.openLog), "copy-failed|old|\(fixture.destination.path)\n")
    }

    func testAlivePIDTimesOutWithoutCopyingReplacingOrOpening() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(try run(fixture, originalPID: ProcessInfo.processInfo.processIdentifier, waitLimit: 1), 1)
        XCTAssertEqual(try text(fixture.result), "exit-timeout\n")
        XCTAssertEqual(try payload(fixture.destination), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.openLog.path))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        XCTAssertFalse(siblings.contains { $0.hasPrefix(".LightStatsUpdate.") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupRecord.path))
        XCTAssertFalse(siblings.contains("move-count"))
    }

    func testWaitsForOriginalProcessToExit() throws {
        let fixture = try makeFixture()
        let original = Process()
        original.executableURL = URL(fileURLWithPath: "/bin/sleep")
        original.arguments = ["0.2"]
        original.standardInput = FileHandle.nullDevice
        original.standardOutput = FileHandle.nullDevice
        original.standardError = FileHandle.nullDevice
        try original.run()
        XCTAssertEqual(try run(fixture, originalPID: original.processIdentifier), 0)
        original.waitUntilExit()
        XCTAssertEqual(try payload(fixture.destination), "new")
        XCTAssertEqual(try text(fixture.result), "installed\n")
    }

    private func assertOldReopened(_ fixture: Fixture, reason: String) throws {
        XCTAssertEqual(try payload(fixture.destination), "old")
        XCTAssertEqual(try text(fixture.result), "\(reason)\n")
        XCTAssertEqual(try text(fixture.openLog), "\(reason)|old|\(fixture.destination.path)\n")
    }

    private func assertBackupReopened(_ fixture: Fixture) throws {
        let backup = try XCTUnwrap(backups(fixture).first)
        XCTAssertEqual(try payload(backup), "old")
        XCTAssertEqual(try text(fixture.result), "rollback-failed\n")
        XCTAssertEqual(try text(fixture.backupRecord), "\(backup.path)\n")
        XCTAssertTrue(try text(fixture.openLog).hasSuffix("rollback-failed|old|\(backup.path)\n"))
    }

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func payload(_ app: URL) throws -> String {
        try text(app.appendingPathComponent("payload"))
    }

    private func backups(_ fixture: Fixture) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
            .filter { $0.hasPrefix(".LightStatsUpdate.") && $0.hasSuffix(".backup.app") }
            .map { fixture.root.appendingPathComponent($0, isDirectory: true) }
    }

    private func run(
        _ fixture: Fixture,
        originalPID: Int32? = nil,
        waitLimit: Int = 100,
        copy: String = "/usr/bin/ditto"
    ) throws -> Int32 {
        // Obtain a real, reaped PID rather than assuming a hard-coded PID is unused.
        let exited = Process()
        exited.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try exited.run()
        exited.waitUntilExit()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", UpdateInstallerService.script, "installer-test",
            String(originalPID ?? exited.processIdentifier),
            fixture.source.path, fixture.destination.path, fixture.result.path,
            fixture.open.path, copy, fixture.move.path, String(waitLimit), "0.01"
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func makeFixture(failedMoves: String = "") throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("installer spaces ' $literal ; \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let source = root.appendingPathComponent("Staged App.app", isDirectory: true)
        let destination = root.appendingPathComponent("Installed App.app", isDirectory: true)
        for (url, value) in [(source, "new"), (destination, "old")] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try value.write(to: url.appendingPathComponent("payload"), atomically: true, encoding: .utf8)
        }
        try failedMoves.write(to: root.appendingPathComponent("failed-moves"), atomically: true, encoding: .utf8)
        let open = try command("fake open", in: root, body: #"""
        ROOT=${0%/*}
        RESULT=$(/bin/cat "$ROOT/result file") || exit 2
        PAYLOAD=$(/bin/cat "$1/payload") || exit 2
        printf '%s|%s|%s\n' "$RESULT" "$PAYLOAD" "$1" >> "$ROOT/open log"
        [ ! -f "$ROOT/fail-all-open" ] || exit 1
        if [ "$PAYLOAD" = new ] && [ -f "$ROOT/fail-new-open" ]; then
            exit 1
        fi
        """#)
        let move = try command("injected mv", in: root, body: #"""
        ROOT=${0%/*}
        COUNT=0
        if [ -f "$ROOT/move-count" ]; then
            read -r COUNT < "$ROOT/move-count"
        fi
        COUNT=$((COUNT + 1))
        printf '%s\n' "$COUNT" > "$ROOT/move-count"
        if [ "$COUNT" -eq 1 ]; then
            RECORDED=$(/bin/cat "$ROOT/result file.backup") || exit 2
            [ "$RECORDED" = "$2" ] || exit 2
            printf '%s\n' "$RECORDED" > "$ROOT/backup-at-first-rename"
        fi
        FAILURES=$(/bin/cat "$ROOT/failed-moves")
        case ",$FAILURES," in
            *",$COUNT,"*) exit 1 ;;
        esac
        exec /bin/mv "$@"
        """#)
        return Fixture(root: root, source: source, destination: destination, open: open, move: move)
    }

    private func command(_ name: String, in root: URL, body: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private struct Fixture {
        let root: URL
        let source: URL
        let destination: URL
        let open: URL
        let move: URL
        var result: URL { root.appendingPathComponent("result file") }
        var backupRecord: URL { result.appendingPathExtension("backup") }
        var openLog: URL { root.appendingPathComponent("open log") }
    }
}
