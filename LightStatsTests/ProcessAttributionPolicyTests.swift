import XCTest
@testable import Light_Stats

final class ProcessAttributionPolicyTests: XCTestCase {
    private func resolve(
        pid: Int32 = 20,
        parent: Int32 = 1,
        responsible: Int32 = 0,
        bundleID: String? = nil,
        path: String? = nil,
        monitored: [Int32: String] = [10: "app"],
        parents: [Int32: Int32] = [:]
    ) -> ProcessGroupResolution? {
        let bundle = ProcessBundleInfo(execPath: path, bundlePath: path.flatMap(ProcessBundleResolver.rootBundlePath), bundleId: bundleID)
        let row = TopProcessInfo(
            pid: pid, parentPid: parent, command: path ?? "worker", memoryBytes: 10,
            identity: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0),
            bundleInfo: bundle, responsiblePid: responsible
        )
        return ProcessAttributionPolicy.resolveGroup(
            for: row, responsiblePid: responsible, processBundleInfo: bundle, responsibleBundleInfo: nil,
            monitoredByPid: monitored, monitoredByBundleId: ["com.example.app": "app"],
            monitoredByBundlePath: ["/Applications/Example.app": "app"], parentByPid: parents
        )
    }

    func testIndependentGUIAppIsNotAbsorbedByItsLaunchingTerminal() {
        let result = resolve(pid: 10, responsible: 30, monitored: [10: "app", 30: "terminal"])
        XCTAssertEqual(result?.groupKey, "app")
        XCTAssertEqual(result?.source, .owningApp)
    }

    func testResponsibleAppOwnsExternalWorkers() {
        XCTAssertEqual(resolve(responsible: 10)?.source, .responsibility)
        XCTAssertEqual(resolve(responsible: 10)?.groupKey, "app")
    }

    func testReparentedCrashHandlerStillBelongsToBundle() {
        let result = resolve(parent: 1, path: "/Applications/Example.app/Contents/Frameworks/crashpad_handler")
        XCTAssertEqual(result?.groupKey, "app", "A launchd parent must not detach a bundled helper from its application")
        XCTAssertEqual(result?.source, .bundle)
    }

    func testHelperSuffixIsRecognizedButUnrelatedBundleIsNot() {
        XCTAssertEqual(resolve(bundleID: "com.example.app.helper.renderer")?.groupKey, "app")
        XCTAssertNil(resolve(bundleID: "com.example.application"))
        XCTAssertNil(resolve(bundleID: "com.example.app.other"))
    }

    func testParentChainAttributionDoesNotGrantTerminationRights() {
        let result = resolve(parent: 30, parents: [30: 40, 40: 10])
        XCTAssertEqual(result?.groupKey, "app")
        XCTAssertEqual(result?.source, .parentProcess)
        XCTAssertFalse(result?.source.canTerminateWithApp ?? true)
    }

    func testParentCyclesAndMissingParentsStopResolution() {
        XCTAssertNil(resolve(parent: 30, parents: [30: 40, 40: 30]))
        XCTAssertNil(resolve(parent: 30))
        var parents: [Int32: Int32] = [:]
        for pid in Int32(30)..<70 { parents[pid] = pid + 1 }
        parents[70] = 10
        XCTAssertNil(resolve(parent: 30, parents: parents), "A malformed deep chain must not hang attribution")
    }

    func testNestedAppAndExtensionPathsKeepOuterApplication() {
        for path in [
            "/Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app/Contents/MacOS/WeChatAppEx",
            "/Applications/WeChat.app/Contents/PlugIns/Widget.appex/Contents/MacOS/Widget"
        ] {
            XCTAssertEqual(ProcessBundleResolver.rootBundlePath(in: path), "/Applications/WeChat.app")
        }
        XCTAssertNil(ProcessBundleResolver.rootBundlePath(in: "/usr/bin/node"))
    }
}
