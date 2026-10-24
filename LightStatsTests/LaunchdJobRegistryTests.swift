import XCTest
@testable import Light_Stats

final class LaunchdJobRegistryTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchdJobRegistryTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func write(_ name: String, _ plist: [String: Any]) {
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let path = directory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: path.path, contents: data)
    }

    private func table() -> [String: String] {
        LaunchdJobRegistry.labelTable(in: [directory.path])
    }

    func testProgramArgumentsNamesTheProgramWhenProgramIsAbsent() {
        write("a.plist", [
            "Label": "cain.com.chargelimiter.daemon",
            "ProgramArguments": ["/Library/Application Support/ChargeLimiter/chargelimiterd", "-daemon"]
        ])
        XCTAssertEqual(
            table()["/Library/Application Support/ChargeLimiter/chargelimiterd"],
            "cain.com.chargelimiter.daemon",
            "Most helpers declare their program as the first argument, not as Program"
        )
    }

    func testProgramWinsOverTheFirstArgument() {
        write("a.plist", [
            "Label": "com.example.job",
            "Program": "/opt/example/job",
            "ProgramArguments": ["/bin/sh", "/opt/example/job"]
        ])
        let table = table()
        XCTAssertEqual(table["/opt/example/job"], "com.example.job")
        XCTAssertNil(
            table["/bin/sh"],
            "An interpreter given as argv[0] is shared, so indexing it would label every shell with this job"
        )
    }

    func testSharedInterpretersAreNeverIndexed() {
        write("a.plist", ["Label": "com.tmex.tmex", "ProgramArguments": ["/bin/bash"]])
        write("b.plist", ["Label": "cain.com.battery", "ProgramArguments": ["/usr/bin/python3"]])
        let table = table()
        XCTAssertNil(
            table["/bin/bash"],
            "One job owning /bin/bash must not make every bash process read as that product"
        )
        XCTAssertNil(table["/usr/bin/python3"])
    }

    func testAJobWithoutAProgramIsSkipped() {
        write("a.plist", ["Label": "com.google.keystone.agent"])
        XCTAssertTrue(table().isEmpty, "An empty job plist must not produce a label out of its name")
    }

    func testAJobInstalledInsideAnApplicationIsNotReached() {
        write("Example.app/Contents/Library/LaunchAgents/x.plist", [
            "Label": "com.example.agent",
            "BundleProgram": "Library/LaunchServices/com.example.agent"
        ])
        XCTAssertTrue(
            table().isEmpty,
            "The three install directories never hold an application, so a job bundled inside one is out of this scan's reach rather than silently half-supported"
        )
    }

    func testTheRegistryOnlyRescansWhenTheDirectoryChanges() {
        write("a.plist", ["Label": "com.example.job", "Program": "/opt/example/job"])
        let registry = LaunchdJobRegistry(directories: [directory.path])
        XCTAssertEqual(registry.label(forProgramPath: "/opt/example/job"), "com.example.job")

        write("b.plist", ["Label": "com.example.second", "Program": "/opt/example/second"])
        XCTAssertNotNil(
            registry.label(forProgramPath: "/opt/example/second"),
            "A newly installed job must be picked up rather than cached out"
        )
        XCTAssertNil(registry.label(forProgramPath: "/opt/example/missing"))
    }
}
