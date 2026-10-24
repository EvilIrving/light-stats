import XCTest
@testable import Light_Stats

final class BackgroundOwnerPolicyTests: XCTestCase {

    private func process(
        pid: pid_t = 100,
        command: String,
        bundlePath: String? = nil,
        bundleId: String? = nil
    ) -> TopProcessInfo {
        TopProcessInfo(
            pid: pid,
            parentPid: 1,
            command: command,
            memoryBytes: 64,
            identity: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0),
            bundleInfo: ProcessBundleInfo(execPath: command, bundlePath: bundlePath, bundleId: bundleId),
            responsiblePid: -1
        )
    }

    // MARK: - Candidate identifiers

    func testJobRoleSuffixIsRemovedSoTheProductIdentifierRemains() {
        XCTAssertEqual(
            BackgroundOwnerPolicy.strippingJobSuffixes("com.netease.uuremote.daemon"),
            ["com.netease.uuremote.daemon", "com.netease.uuremote"],
            "A privileged helper's label names its role; the product is the label without that role"
        )
        XCTAssertEqual(
            BackgroundOwnerPolicy.strippingJobSuffixes("cain.com.chargelimiter.daemon"),
            ["cain.com.chargelimiter.daemon", "cain.com.chargelimiter"]
        )
    }

    func testAProductIdentifierIsNotShortenedFurther() {
        XCTAssertEqual(
            BackgroundOwnerPolicy.strippingJobSuffixes("com.netease.uuremote"),
            ["com.netease.uuremote"],
            "Stripping must stop at the first component that is not a job role, or a vendor prefix could name the wrong application"
        )
    }

    func testRepeatedJobRolesAreEachRemoved() {
        XCTAssertEqual(
            BackgroundOwnerPolicy.strippingJobSuffixes("io.tailscale.ipn.macsys.network-extension"),
            ["io.tailscale.ipn.macsys.network-extension", "io.tailscale.ipn.macsys"]
        )
    }

    func testTheProcessesOwnBundleIsOfferedBeforeItsJobLabel() {
        let row = process(
            command: "/Applications/UURemote.app/Contents/MacOS/UURemoteDaemon",
            bundlePath: "/Applications/UURemote.app",
            bundleId: "com.netease.uuremote"
        )
        XCTAssertEqual(
            BackgroundOwnerPolicy.candidateIdentifiers(for: row, launchdLabel: "com.netease.uuremote.daemon"),
            ["com.netease.uuremote", "com.netease.uuremote.daemon"],
            "A process inside an application bundle already names its product, so the job label is the fallback"
        )
    }

    func testIdentifiersAreNotRepeatedWhenBothSourcesAgree() {
        let row = process(
            command: "/Applications/AltTab.app/Contents/MacOS/AltTab",
            bundlePath: "/Applications/AltTab.app",
            bundleId: "com.lwouis.alt-tab-macos"
        )
        XCTAssertEqual(
            BackgroundOwnerPolicy.candidateIdentifiers(for: row, launchdLabel: "com.lwouis.alt-tab-macos"),
            ["com.lwouis.alt-tab-macos"]
        )
    }

    // MARK: - Owner resolution

    func testFirstResolvingIdentifierWins() {
        let row = process(
            command: "/Library/PrivilegedHelperTools/com.silora.mobileclient.mac.helper/silora-helper"
        )
        var asked: [String] = []
        let owner = BackgroundOwnerPolicy.owner(for: row, launchdLabel: "com.silora.mobileclient.mac.helper") { id in
            asked.append(id)
            return id == "com.silora.mobileclient.mac"
                ? BackgroundOwnerPolicy.Owner(key: id, name: "Silora 希环")
                : nil
        }
        XCTAssertEqual(owner?.name, "Silora 希环")
        XCTAssertEqual(
            asked,
            ["com.silora.mobileclient.mac.helper", "com.silora.mobileclient.mac"],
            "The identifier is tried as it stands before the job role is removed"
        )
    }

    func testUnresolvedIdentifiersLeaveTheProcessUnowned() {
        let row = process(command: "/Users/actor/.bun/bin/bun")
        XCTAssertNil(
            BackgroundOwnerPolicy.owner(for: row, launchdLabel: nil) { _ in nil },
            "A plain binary belongs to no installed application, and guessing one would name the wrong product"
        )
    }

    func testAJobLabelAloneIsEnoughWhenTheBinarySitsOutsideEveryBundle() {
        let row = process(command: "/Library/Application Support/ChargeLimiter/chargelimiterd")
        let owner = BackgroundOwnerPolicy.owner(for: row, launchdLabel: "cain.com.chargelimiter.daemon") { id in
            id == "cain.com.chargelimiter" ? BackgroundOwnerPolicy.Owner(key: id, name: "Charge Limiter") : nil
        }
        XCTAssertEqual(owner?.name, "Charge Limiter")
    }
}
