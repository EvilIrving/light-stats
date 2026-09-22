import XCTest
@testable import Light_Stats

@MainActor
final class WindowVisibilityServiceTests: XCTestCase {
    private let own = ProcessIdentity(pid: 100, startSeconds: 1, startMicroseconds: 0)
    private let dragged = ProcessIdentity(pid: 101, startSeconds: 2, startMicroseconds: 0)
    private let other = ProcessIdentity(pid: 102, startSeconds: 3, startMicroseconds: 0)
    private let manual = ProcessIdentity(pid: 103, startSeconds: 4, startMicroseconds: 0)

    func testFalseRequestReturnsStillHideAndRestoreOnConsecutiveShakes() async throws {
        let fixture = makeFixture()
        fixture.requestResult = false
        let service = makeService(fixture)

        let first = await service.perform(nil, keeping: dragged.pid)
        XCTAssertEqual(first?.command, .hideOthers)
        XCTAssertEqual(first?.changed, 1, "Observed hidden state must win over AppKit's false return")
        XCTAssertEqual(first?.succeeded, true)
        XCTAssertEqual(service.hiddenCount, 1)
        XCTAssertTrue(fixture.isHidden(other))
        XCTAssertFalse(fixture.isHidden(dragged))
        XCTAssertFalse(fixture.isHidden(own))

        let second = await service.perform(nil, keeping: dragged.pid)
        XCTAssertEqual(second?.command, .restore, "A second shake must work without a shortcut first")
        XCTAssertEqual(second?.changed, 1)
        XCTAssertEqual(second?.succeeded, true)
        XCTAssertFalse(fixture.isHidden(other))
        XCTAssertTrue(fixture.isHidden(manual), "The user's pre-existing hides must remain hidden")
        XCTAssertEqual(service.hiddenCount, 0)
        XCTAssertEqual(fixture.requests.map(\.identity), [other, other])
    }

    func testTrueRequestReturnWithoutStateChangeIsNotSuccess() async {
        let fixture = makeFixture()
        fixture.requestResult = true
        fixture.blocked = [other]
        let service = makeService(fixture)
        let result = await service.perform(nil, keeping: dragged.pid)
        XCTAssertEqual(result?.succeeded, false, "Sending a hide request is not proof that the app hid")
        XCTAssertEqual(result?.failed, 1)
        XCTAssertEqual(result?.changed, 0)
        XCTAssertEqual(service.hiddenCount, 0)
    }

    func testFailedRestoreKeepsHistoryAndNextShakeRetries() async {
        let fixture = makeFixture()
        let service = makeService(fixture)
        _ = await service.perform(nil, keeping: dragged.pid)
        fixture.blocked = [other]
        let failed = await service.perform(nil, keeping: dragged.pid)
        XCTAssertEqual(failed?.command, .restore)
        XCTAssertEqual(failed?.succeeded, false)
        XCTAssertEqual(service.hiddenCount, 1, "An unsuccessful restore must not consume undo")

        fixture.blocked = []
        let retry = await service.perform(nil, keeping: dragged.pid)
        XCTAssertEqual(retry?.command, .restore)
        XCTAssertEqual(retry?.succeeded, true)
        XCTAssertEqual(service.hiddenCount, 0)
    }

    func testVisibilityConfirmationWaitsForDelayedStateChange() async {
        let fixture = makeFixture()
        fixture.delay = 3
        let service = makeService(fixture)
        let result = await service.perform(nil, keeping: dragged.pid)
        XCTAssertEqual(result?.succeeded, true)
        XCTAssertEqual(fixture.waits, 3, "Confirmation must allow the run loop to refresh AppKit state")
    }

    func testRelaunchRestoresOnlySavedProcessIdentities() async throws {
        let fixture = makeFixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("visibility.json")
        let firstService = makeService(fixture, storageURL: url)
        _ = await firstService.perform(nil, keeping: dragged.pid)
        let replacement = makeService(fixture, storageURL: url)
        let result = await replacement.perform(nil, keeping: dragged.pid)
        XCTAssertEqual(result?.command, .restore, "Replacing Light Stats must not strand applications it hid")
        XCTAssertFalse(fixture.isHidden(other))
        XCTAssertTrue(fixture.isHidden(manual))
        let empty = try JSONDecoder().decode(Set<ProcessIdentity>.self, from: Data(contentsOf: url))
        XCTAssertTrue(empty.isEmpty, "Confirmed restores must also clear the persisted undo")
    }

    func testReusedPIDIsNeverRestored() async {
        let fixture = makeFixture()
        let service = makeService(fixture)
        _ = await service.perform(nil, keeping: dragged.pid)
        let reused = ProcessIdentity(pid: other.pid, startSeconds: 99, startMicroseconds: 0)
        fixture.apps.removeAll { $0.identity == other }
        fixture.apps.append(.init(identity: reused, isHidden: true))
        fixture.requests.removeAll()
        let result = await service.perform(.restore, keeping: dragged.pid)
        XCTAssertEqual(result?.reason, "noTargets")
        XCTAssertTrue(fixture.requests.isEmpty, "A new process at an old PID does not belong to our hide")
        XCTAssertTrue(fixture.isHidden(reused))
        XCTAssertEqual(service.hiddenCount, 0)
    }

    func testUserRevealingApplicationsResetsTheShakeDirection() async {
        let fixture = makeFixture()
        let service = makeService(fixture)
        _ = await service.perform(nil, keeping: dragged.pid)
        fixture.apps = fixture.apps.map { app in
            var updated = app
            if app.identity == other { updated.isHidden = false }
            return updated
        }
        let result = await service.perform(nil, keeping: dragged.pid)
        XCTAssertEqual(result?.command, .hideOthers, "A stale record must not turn the next shake into a no-op restore")
        XCTAssertEqual(result?.succeeded, true)
    }

    func testExplicitHideAndShakeShareConfirmedHistory() async {
        let fixture = makeFixture()
        let service = makeService(fixture)
        _ = await service.perform(.hideOthers, keeping: dragged.pid)
        let result = await service.perform(nil, keeping: dragged.pid)
        XCTAssertEqual(result?.command, .restore)
        XCTAssertFalse(fixture.isHidden(other))
    }

    func testHideAllIncludesDraggedApplicationButExcludesOurOwn() async {
        let fixture = makeFixture()
        let service = makeService(fixture)
        let result = await service.perform(.hideAll, keeping: dragged.pid)
        XCTAssertEqual(result?.changed, 2)
        XCTAssertTrue(fixture.isHidden(dragged))
        XCTAssertFalse(fixture.isHidden(own))
        _ = await service.perform(.restore, keeping: nil)
        XCTAssertFalse(fixture.isHidden(dragged))
        XCTAssertTrue(fixture.isHidden(manual))
    }

    func testForgetDuringConfirmationCannotResurrectHistory() async {
        let fixture = makeFixture()
        let service = makeService(fixture)
        fixture.duringWait = { service.forgetHistory() }
        let result = await service.perform(nil, keeping: dragged.pid)
        XCTAssertEqual(result?.reason, "cancelled")
        XCTAssertEqual(service.hiddenCount, 0, "Disabling the feature must win over an in-flight confirmation")
    }

    func testOverlappingCommandDoesNotUndoAnUnconfirmedHide() async {
        let fixture = makeFixture()
        let service = makeService(fixture)
        fixture.duringWait = {
            let overlapping = await service.perform(nil, keeping: self.dragged.pid)
            XCTAssertNil(overlapping, "Visibility operations must not interleave while AppKit catches up")
        }
        _ = await service.perform(nil, keeping: dragged.pid)
        XCTAssertTrue(fixture.isHidden(other))
        XCTAssertEqual(service.hiddenCount, 1)
    }

    func testNoTargetsDoesNotReportSuccessOrAdoptManualHides() async {
        let fixture = Fixture(apps: [.init(identity: dragged, isHidden: false), .init(identity: manual, isHidden: true)])
        let service = makeService(fixture)
        let result = await service.perform(nil, keeping: dragged.pid)
        XCTAssertEqual(result?.reason, "noTargets")
        XCTAssertEqual(result?.succeeded, false)
        XCTAssertEqual(service.hiddenCount, 0)
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testPartialRestoreRetainsOnlyTheApplicationsStillHidden() async {
        let fixture = makeFixture()
        let service = makeService(fixture)
        _ = await service.perform(.hideAll, keeping: nil)
        fixture.blocked = [other]
        let result = await service.perform(.restore, keeping: nil)
        XCTAssertEqual(result?.changed, 1)
        XCTAssertEqual(result?.failed, 1)
        XCTAssertEqual(result?.succeeded, false)
        XCTAssertEqual(service.hiddenCount, 1)
        XCTAssertFalse(fixture.isHidden(dragged))
        XCTAssertTrue(fixture.isHidden(other))
    }

    func testAccessoryApplicationsAreNotHidden() async {
        let fixture = Fixture(apps: [.init(identity: other, isHidden: false, isRegular: false)])
        let service = makeService(fixture)
        let result = await service.perform(.hideAll, keeping: nil)
        XCTAssertEqual(result?.reason, "noTargets")
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testForgetAlsoClearsHistoryAcrossRelaunch() async throws {
        let fixture = makeFixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("visibility.json")
        let service = makeService(fixture, storageURL: url)
        _ = await service.perform(nil, keeping: dragged.pid)
        service.forgetHistory()
        let replacement = makeService(fixture, storageURL: url)
        XCTAssertEqual(replacement.hiddenCount, 0)
        XCTAssertTrue(fixture.isHidden(other), "Disabling the feature must not reveal applications")
    }

    private func makeFixture() -> Fixture {
        Fixture(apps: [
            .init(identity: own, isHidden: false), .init(identity: dragged, isHidden: false),
            .init(identity: other, isHidden: false), .init(identity: manual, isHidden: true)
        ])
    }

    private func makeService(_ fixture: Fixture, storageURL: URL? = nil) -> WindowVisibilityService {
        WindowVisibilityService(client: fixture.client, storageURL: storageURL, ownPID: own.pid)
    }

    @MainActor
    private final class Fixture {
        var apps: [WindowVisibilityService.Application]
        var requests: [(identity: ProcessIdentity, hidden: Bool)] = []
        var blocked: Set<ProcessIdentity> = []
        var requestResult = false
        var delay = 1
        var waits = 0
        var duringWait: (() async -> Void)?
        private var pending: [ProcessIdentity: Bool] = [:]

        init(apps: [WindowVisibilityService.Application]) { self.apps = apps }

        func isHidden(_ identity: ProcessIdentity) -> Bool {
            apps.first { $0.identity == identity }?.isHidden == true
        }

        var client: WindowVisibilityService.Client {
            .init(applications: { self.apps }, request: { identity, hidden in
                self.requests.append((identity, hidden))
                self.pending[identity] = hidden
                return self.requestResult
            }, wait: {
                self.waits += 1
                if self.waits >= self.delay {
                    for index in self.apps.indices where !self.blocked.contains(self.apps[index].identity) {
                        if let hidden = self.pending.removeValue(forKey: self.apps[index].identity) {
                            self.apps[index].isHidden = hidden
                        }
                    }
                }
                await self.duringWait?()
            })
        }
    }
}
