//
//  AppBundleDropSourceTests.swift
//  Light Stats
//

import XCTest
@testable import Light_Stats

/// Which bundle the guide puts on the pasteboard.
///
/// Both rules here fail **invisibly**: System Settings accepts the drop, shows a row, and the
/// permission still never reaches the running app — so the only place the refusal can be caught is
/// before the drag starts.
final class AppBundleDropSourceTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppBundleDropSourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeApp(named name: String) throws -> URL {
        let bundle = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        return bundle
    }

    // MARK: - Accepting

    func testAnExistingAppBundleIsOffered() throws {
        let bundle = try makeApp(named: "Light Stats.app")
        XCTAssertEqual(AppBundleDropSource.resolvedBundleURL(from: bundle)?.path, bundle.path)
    }

    func testASymlinkedAppIsResolvedBeforeAnythingElse() throws {
        let bundle = try makeApp(named: "Light Stats.app")
        let link = root.appendingPathComponent("Shortcut.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle)
        XCTAssertEqual(
            AppBundleDropSource.resolvedBundleURL(from: link)?.resolvingSymlinksInPath().path,
            bundle.resolvingSymlinksInPath().path,
            "the list has to remember the real bundle, not a link that can be repointed"
        )
    }

    // MARK: - Refusing

    func testATranslocatedAppIsRefused() {
        let translocated = URL(fileURLWithPath:
            "/private/var/folders/xy/abc/T/AppTranslocation/1B7A-4C/d/Light Stats.app")
        XCTAssertTrue(AppBundleDropSource.isTranslocated(translocated))
        XCTAssertNil(
            AppBundleDropSource.resolvedBundleURL(from: translocated),
            "a DMG-run copy's path stops existing when the process quits, so the granted row would refer to nothing"
        )
    }

    func testTheTranslocationTestRunsOnTheResolvedPath() throws {
        // `/var` is a symlink to `/private/var`; only the resolved path carries the marker.
        let linkParent = root.appendingPathComponent("AppTranslocation/1B7A-4C/d", isDirectory: true)
        try FileManager.default.createDirectory(at: linkParent, withIntermediateDirectories: true)
        let bundle = linkParent.appendingPathComponent("Light Stats.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let resolved = bundle.resolvingSymlinksInPath()
        XCTAssertTrue(AppBundleDropSource.isTranslocated(resolved))
        XCTAssertNil(
            AppBundleDropSource.resolvedBundleURL(from: bundle),
            "resolving after the test would have let a translocated copy through"
        )
    }

    func testSomethingThatIsNotAnAppIsRefused() throws {
        let file = root.appendingPathComponent("notes.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNil(AppBundleDropSource.resolvedBundleURL(from: file))
    }

    func testAMissingBundleIsRefused() {
        let missing = root.appendingPathComponent("Not Installed.app", isDirectory: true)
        XCTAssertNil(
            AppBundleDropSource.resolvedBundleURL(from: missing),
            "a path that does not exist cannot be dragged into a list that will look it up later"
        )
    }
}
