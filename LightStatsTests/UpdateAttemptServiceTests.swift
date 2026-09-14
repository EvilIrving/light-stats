import XCTest
@testable import Light_Stats

final class UpdateAttemptServiceTests: XCTestCase {
    func testInterruptedAttemptSurvivesRelaunchAndStaysWithItsBundle() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = directory.appendingPathComponent("Light Stats.app")
        let service = UpdateAttemptService(directory: directory)
        let release = try fixtureRelease()
        try await service.begin(sourceVersion: "1.9.2-beta.7", release: release, destination: bundle)
        try await service.advance(to: "verifying")

        await service.releaseOwnership() // Simulate the old app exiting before the next process starts.
        let relaunched = UpdateAttemptService(directory: directory)
        let pending = try await relaunched.pending(for: bundle)
        let attempt = try XCTUnwrap(pending)
        XCTAssertEqual(attempt.stage, "verifying")
        XCTAssertEqual(attempt.sourceVersion, "1.9.2-beta.7")
        XCTAssertEqual(attempt.targetVersion, "v1.9.4")
        let otherBundle = try await relaunched.pending(for: directory.appendingPathComponent("Debug.app"))
        XCTAssertNil(otherBundle)
        XCTAssertFalse(UpdateAttemptService.succeeded(attempt: attempt, currentVersion: "1.9.2-beta.7", result: nil))
        try await relaunched.clear()
        let cleared = try await relaunched.pending(for: bundle)
        XCTAssertNil(cleared)
    }

    func testOnlyInstalledTargetVersionConfirmsSuccessAndNewAttemptClearsOldResult() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = UpdateAttemptService(directory: directory)
        let bundle = directory.appendingPathComponent("Light Stats.app")
        let release = try fixtureRelease()
        try await service.begin(sourceVersion: "1.9.3", release: release, destination: bundle)
        let pending = try await service.pending(for: bundle)
        let attempt = try XCTUnwrap(pending)
        XCTAssertFalse(UpdateAttemptService.succeeded(attempt: attempt, currentVersion: "1.9.3", result: "installed"))
        XCTAssertFalse(UpdateAttemptService.succeeded(attempt: attempt, currentVersion: "1.9.4", result: "relaunch-failed"))
        XCTAssertFalse(UpdateAttemptService.succeeded(attempt: attempt, currentVersion: "1.9.4", result: nil))
        XCTAssertTrue(UpdateAttemptService.succeeded(attempt: attempt, currentVersion: "1.9.4", result: "installed"))

        let resultURL = await service.resultURL
        try "installed\n".write(to: resultURL, atomically: true, encoding: .utf8)
        let result = try await service.result()
        XCTAssertEqual(result, "installed")
        try await service.clear()
        try "installed\n".write(to: resultURL, atomically: true, encoding: .utf8)
        try await service.begin(sourceVersion: "1.9.3", release: release, destination: bundle)
        let reset = try await service.result()
        XCTAssertNil(reset)
    }

    func testBackupRelaunchFindsReceiptAndOnlyConfirmedSuccessRemovesBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = UpdateAttemptService(directory: directory.appendingPathComponent("state"))
        let bundle = directory.appendingPathComponent("Light Stats.app")
        let backup = directory.appendingPathComponent(".LightStatsUpdate.fixture.backup.app")
        let release = try fixtureRelease()
        try await service.begin(sourceVersion: "1.9.3", release: release, destination: bundle)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let resultURL = await service.resultURL
        let backupRecord = resultURL.appendingPathExtension("backup")
        try backup.path.write(to: backupRecord, atomically: true, encoding: .utf8)
        let fromBackup = try await service.pending(for: backup)
        XCTAssertNotNil(fromBackup)
        try await service.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))

        try await service.begin(sourceVersion: "1.9.3", release: release, destination: bundle)
        try backup.path.write(to: backupRecord, atomically: true, encoding: .utf8)
        try await service.clear(removeBackup: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testBackupRecordCannotDeleteAnUnrelatedApplication() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = UpdateAttemptService(directory: directory)
        let unrelated = directory.appendingPathComponent("Other.app")
        let bundle = directory.appendingPathComponent("Light Stats.app")
        try await service.begin(sourceVersion: "1.9.3", release: fixtureRelease(), destination: bundle)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let resultURL = await service.resultURL
        try unrelated.path.write(to: resultURL.appendingPathExtension("backup"), atomically: true, encoding: .utf8)
        let unrelatedReceipt = try await service.pending(for: unrelated)
        XCTAssertNil(unrelatedReceipt)
        try await service.clear(removeBackup: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testInstallerInheritsOwnershipAndBlocksRecoveryUntilItExits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = directory.appendingPathComponent("Light Stats.app")
        let service = UpdateAttemptService(directory: directory)
        try await service.begin(sourceVersion: "1.9.3", release: fixtureRelease(), destination: bundle)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "/bin/sleep 0.4"]
        child.standardInput = try await service.installerOwnership()
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        await service.releaseOwnership()

        let relaunched = UpdateAttemptService(directory: directory)
        do {
            _ = try await relaunched.pending(for: bundle)
            XCTFail("Recovery must not consume the running installer's receipt")
        } catch UpdateAttemptService.AttemptError.busy { }
        do {
            try await relaunched.begin(sourceVersion: "1.9.3", release: fixtureRelease(), destination: bundle)
            XCTFail("A second process must not start another installer")
        } catch UpdateAttemptService.AttemptError.busy { }
        while child.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        let pending = try await relaunched.pending(for: bundle)
        XCTAssertNotNil(pending)
        try await relaunched.clear()
    }

    func testNewAttemptCannotOverwriteAnUnacknowledgedResult() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = UpdateAttemptService(directory: directory)
        let bundle = directory.appendingPathComponent("Light Stats.app")
        let release = try fixtureRelease()
        try await service.begin(sourceVersion: "1.9.3", release: release, destination: bundle)
        do {
            try await service.begin(sourceVersion: "1.9.4", release: release, destination: bundle)
            XCTFail("Pending attempts require feedback before another install")
        } catch UpdateAttemptService.AttemptError.pending { }
        let pending = try await service.pending(for: bundle)
        XCTAssertEqual(pending?.sourceVersion, "1.9.3")
        try await service.clear()
    }

    func testHiddenRecoveryBundleCannotBecomeTheNextInstallationDestination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backup = directory.appendingPathComponent(".LightStatsUpdate.fixture.backup.app")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        do {
            try await UpdateService().validateDestination(backup)
            XCTFail("A recovered backup requires manual restoration to Applications")
        } catch UpdateService.UpdateError.destinationNotWritable { }
    }

    private func fixtureRelease() throws -> ReleaseInfo {
        try XCTUnwrap(ReleaseInfo(manifest: Data(#"{"version":"1.9.4","file":"Light-Stats-1.9.4.dmg"}"#.utf8)))
    }
}
