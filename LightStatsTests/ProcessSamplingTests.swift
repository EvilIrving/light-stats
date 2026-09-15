import Darwin
import XCTest
@testable import Light_Stats

final class ProcessSamplingTests: XCTestCase {
    private let identity = ProcessIdentity(pid: 42, startSeconds: 100, startMicroseconds: 123)

    func testReusedPIDCannotReceiveAnySignal() {
        let reused = ProcessIdentity(pid: 42, startSeconds: 101, startMicroseconds: 123)
        for signal in [SIGTERM, SIGKILL] {
            var delivered = false
            XCTAssertFalse(ProcessSignalGuard.send(signal, to: identity, readIdentity: { _ in reused }, deliver: { _, _ in
                delivered = true
                return 0
            }), "A stale application row must never signal the replacement process")
            XCTAssertFalse(delivered)
        }
    }

    func testEscalationRechecksIdentityAfterGracefulSignal() {
        var current: ProcessIdentity? = identity
        var signals: [Int32] = []
        let read: (Int32) -> ProcessIdentity? = { _ in current }
        let deliver: (Int32, Int32) -> Int32 = { _, signal in signals.append(signal); return 0 }
        XCTAssertTrue(ProcessSignalGuard.send(SIGTERM, to: identity, readIdentity: read, deliver: deliver))
        current = ProcessIdentity(pid: 42, startSeconds: 100, startMicroseconds: 124)
        XCTAssertFalse(ProcessSignalGuard.send(SIGKILL, to: identity, readIdentity: read, deliver: deliver))
        XCTAssertEqual(signals, [SIGTERM], "An intervening restart must block escalation, even within the same second")
    }

    func testMissingIdentityFailsClosed() {
        XCTAssertFalse(ProcessSignalGuard.send(SIGKILL, to: identity, readIdentity: { _ in nil }, deliver: { _, _ in
            XCTFail("Unknown process identity must not permit termination")
            return 0
        }))
    }

    func testSignalFailureIsNotReportedAsSuccess() {
        XCTAssertFalse(ProcessSignalGuard.send(SIGTERM, to: identity, readIdentity: { _ in self.identity }, deliver: { _, _ in -1 }))
    }

    func testInvalidPIDCannotTargetAProcessGroup() {
        let invalid = ProcessIdentity(pid: -1, startSeconds: 0, startMicroseconds: 0)
        XCTAssertFalse(ProcessSignalGuard.send(SIGKILL, to: invalid, readIdentity: { _ in invalid }, deliver: { _, _ in
            XCTFail("Nonpositive PIDs target process groups and must never reach kill")
            return 0
        }))
    }

    func testMoreThanEightyProcessesKeepOneMemoryMetric() {
        let footprints: [UInt64?] = Array(repeating: 10, count: 100)
        let summary = ProcessMemorySummary(footprints)
        XCTAssertEqual(summary.knownBytes, 1_000, "Small helper processes must be included with the same footprint metric")
        XCTAssertEqual(summary.unavailableCount, 0)
    }

    func testMissingFootprintIsNotZeroOrRSS() {
        let summary = ProcessMemorySummary([100, nil, 0, nil, 200])
        XCTAssertEqual(summary.knownBytes, 300)
        XCTAssertEqual(summary.unavailableCount, 2, "Zero is a valid reading; unavailable data makes the total incomplete")
        XCTAssertEqual(ProcessMemorySummary([]).knownBytes, 0)
        XCTAssertEqual(ProcessMemorySummary([UInt64.max, 1]).knownBytes, UInt64.max)
    }

    func testNativeSamplingCanReadTheTestHostWithoutTaskPorts() async {
        let sampler = ProcessSampler()
        let rows = await sampler.sample()
        let pid = getpid()
        guard let row = rows.first(where: { $0.pid == pid }) else {
            XCTFail("Native enumeration must include this process")
            return
        }
        XCTAssertEqual(row.identity, ProcessIdentityReader.read(pid))
        guard let fallback = ProcessIdentityReader.fallbackBSDInfo(for: pid) else {
            XCTFail("The BSD sysctl fallback must preserve identity when task-accounting access is unavailable")
            return
        }
        XCTAssertEqual(row.identity, ProcessIdentityReader.identity(pid: pid, info: fallback),
                       "Switching between libproc and sysctl must not invent a new process identity")
        XCTAssertNotNil(row.memoryBytes, "The current user's process must expose footprint without Accessibility or task_for_pid")
        XCTAssertGreaterThan(row.memoryBytes ?? 0, 0)
        let cached = await sampler.sample()
        XCTAssertEqual(cached.map(\.identity), rows.map(\.identity), "Adjacent consumers should share one snapshot")
    }
}
