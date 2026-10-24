import XCTest
@testable import Light_Stats

final class ChildProcessDisplayPolicyTests: XCTestCase {

    private func process(
        pid: pid_t = 100,
        command: String,
        memoryBytes: UInt64? = 64
    ) -> TopProcessInfo {
        TopProcessInfo(
            pid: pid,
            parentPid: 1,
            command: command,
            memoryBytes: memoryBytes,
            identity: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0),
            bundleInfo: ProcessBundleInfo(execPath: command, bundlePath: nil, bundleId: nil),
            responsiblePid: pid
        )
    }

    // MARK: - Naming

    func testNestedHelperBundleNamesTheMemberNotItsHostApplication() {
        let chrome = process(
            command: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/"
                + "Versions/156.0.0/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        )
        XCTAssertEqual(
            ChildProcessDisplayPolicy.label(for: chrome),
            "Google Chrome Helper (Renderer)",
            "Every Chrome member shares the outer Google Chrome.app name, so only the nested helper bundle names the member"
        )
    }

    func testHelperInsideItsHostWithoutANestedBundleIsNamedByItsExecutable() {
        let wxocr = process(command: "/Applications/WeChat.app/Contents/Frameworks/wxocr")
        XCTAssertEqual(
            ChildProcessDisplayPolicy.label(for: wxocr),
            "wxocr",
            "A helper that lives directly inside its host has no nested bundle, so naming it after the host hides which helper it is"
        )
    }

    func testExecutableOutsideAnyBundleIsNamedByItsFile() {
        XCTAssertEqual(
            ChildProcessDisplayPolicy.label(for: process(command: "/opt/homebrew/Cellar/tmux/3.6b/bin/tmux")),
            "tmux"
        )
    }

    func testBareProcessNameIsKeptAsIs() {
        XCTAssertEqual(
            ChildProcessDisplayPolicy.label(for: process(command: "silora-helper")),
            "silora-helper",
            "A sampler row without a resolvable path still has to render a name"
        )
    }

    func testTrailingSeparatorFallsBackToTheRawCommandInsteadOfAnEmptyLabel() {
        XCTAssertEqual(ChildProcessDisplayPolicy.label(for: process(command: "/usr/bin/env/")), "/usr/bin/env/")
    }

    func testOwnerNamePrefixIsDroppedSoTheMemberKeepsItsOwnWords() {
        XCTAssertEqual(
            ChildProcessDisplayPolicy.label(
                forCommand: "/Applications/Google Chrome.app/Contents/Frameworks/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
                ownerName: "Google Chrome"
            ),
            "Helper (Renderer)",
            "Repeating the application name in every helper row spends the whole column on words the row already carries"
        )
    }

    func testOwnerPrefixIsOnlyDroppedOnAWholeWord() {
        XCTAssertEqual(
            ChildProcessDisplayPolicy.label(
                forCommand: "/Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app/Contents/MacOS/WeChatAppEx",
                ownerName: "WeChat"
            ),
            "WeChatAppEx",
            "WeChatAppEx is not the WeChat name plus a word, so it must not be shortened into a different name"
        )
        XCTAssertEqual(
            ChildProcessDisplayPolicy.label(
                forCommand: "/Applications/Figma.app/Contents/MacOS/Figma",
                ownerName: "Figma"
            ),
            "Figma",
            "The owning process has no member name after its own, so it keeps its full name"
        )
    }

    func testExecutableNameIsExtractedForTheNameBasedFilters() {
        XCTAssertEqual(
            ChildProcessDisplayPolicy.executableName(forCommand: "/opt/homebrew/Cellar/watchman/2025.11.10.00/bin/watchman"),
            "watchman",
            "ShouldShowProcess matches executable names, so it must not be handed a full path"
        )
        XCTAssertEqual(ChildProcessDisplayPolicy.executableName(forCommand: "cmux"), "cmux")
    }

    // MARK: - Repeated labels

    func testRepeatedLabelsAreTheOnlyOnesThatShowThePid() {
        let entries = ChildProcessDisplayPolicy.entries(for: [
            process(pid: 10, command: "/Applications/Figma.app/Contents/MacOS/Figma"),
            process(pid: 11, command: "/Users/actor/.local/share/fnm/node-versions/v24/bin/node"),
            process(pid: 12, command: "/Users/actor/.local/share/fnm/node-versions/v24/bin/node"),
            process(pid: 13, command: "/opt/homebrew/Cellar/tmux/3.6b/bin/tmux")
        ])
        XCTAssertEqual(entries.map(\.showsPID), [false, true, true, false])
        XCTAssertEqual(
            entries.filter(\.showsPID).map(\.pid),
            [11, 12],
            "Six `node` members are indistinguishable by label, so the pid is the only discriminator"
        )
    }

    func testEntriesKeepTheSampledMemoryOfEachMember() {
        let entries = ChildProcessDisplayPolicy.entries(for: [
            process(pid: 1, command: "/Applications/Figma.app/Contents/Frameworks/Figma Helper.app/Contents/MacOS/a", memoryBytes: 4_294_967_296),
            process(pid: 2, command: "/Applications/Figma.app/Contents/Frameworks/Figma Helper.app/Contents/MacOS/b", memoryBytes: nil)
        ])
        XCTAssertEqual(entries[0].memoryBytes, 4_294_967_296)
        XCTAssertNil(
            entries[1].memoryBytes,
            "An unavailable footprint stays unavailable rather than becoming zero"
        )
        XCTAssertTrue(entries.allSatisfy(\.showsPID), "Both rows carry the same label")
    }

    func testDetailKeepsTheFullPathForTheTooltip() {
        let command = "/Applications/Figma.app/Contents/MacOS/Figma"
        let entries = ChildProcessDisplayPolicy.entries(for: [process(pid: 99, command: command)])
        XCTAssertEqual(entries[0].detail, command)
    }

    // MARK: - Ordering

    func testOwningProcessIsListedFirstSoTheDetailCountMatchesTheRowCount() {
        let members = [
            process(pid: 30, command: "/Applications/Figma.app/Contents/MacOS/Figma Helper", memoryBytes: 900),
            process(pid: 20, command: "/Applications/Figma.app/Contents/MacOS/Figma Helper", memoryBytes: 700),
            process(pid: 10, command: "/Applications/Figma.app/Contents/MacOS/Figma", memoryBytes: 5)
        ]
        let ordered = ChildProcessDisplayPolicy.orderedMembers(members, ownerPID: 10)
        XCTAssertEqual(
            ordered.map(\.pid),
            [10, 30, 20],
            "The owning process is what the row count and close button refer to, so it heads its own detail list"
        )
    }

    func testOrderingKeepsMemoryOrderWhenNoMemberOwnsTheGroup() {
        let members = [
            process(pid: 30, command: "bun", memoryBytes: 100),
            process(pid: 20, command: "tmux", memoryBytes: 700)
        ]
        let ordered = ChildProcessDisplayPolicy.orderedMembers(members, ownerPID: AppGroup.backgroundGroupId)
        XCTAssertEqual(ordered.map(\.pid), [20, 30], "The background bucket has no owning process to promote")
    }

    func testUnavailableMemorySortsLastAndEqualMemoryFallsBackToPid() {
        let members = [
            process(pid: 42, command: "node", memoryBytes: nil),
            process(pid: 41, command: "node", memoryBytes: 10),
            process(pid: 40, command: "node", memoryBytes: 10)
        ]
        let ordered = ChildProcessDisplayPolicy.orderedMembers(members, ownerPID: -1)
        XCTAssertEqual(ordered.map(\.pid), [40, 41, 42])
    }
}
