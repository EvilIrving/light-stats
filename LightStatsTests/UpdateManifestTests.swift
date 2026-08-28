//
//  UpdateManifestTests.swift
//  Light Stats Tests
//
//  R2 channel marker (`latest-stable.json` / `latest-beta.json`) parsing, the
//  source of truth for in-app auto-update checks.
//

import XCTest
@testable import Light_Stats

final class UpdateManifestTests: XCTestCase {

    func testManifestParsesVersionFileAndNotes() throws {
        let data = Data("""
        {"version":"1.9.2","file":"Light-Stats-1.9.2.dmg","notes":"## v1.9.2\\n- 新功能"}
        """.utf8)
        let release = try XCTUnwrap(ReleaseInfo(manifest: data))
        XCTAssertEqual(release.version, SemanticVersion("1.9.2"))
        XCTAssertEqual(release.tagName, "v1.9.2")
        XCTAssertEqual(release.downloadURL.absoluteString,
                       "https://download.onecat.dev/Light-Stats-1.9.2.dmg")
        XCTAssertEqual(release.sha256URL?.absoluteString,
                       "https://download.onecat.dev/Light-Stats-1.9.2.dmg.sha256")
        XCTAssertTrue(release.releaseNotes.contains("新功能"))
        XCTAssertTrue(release.htmlURL.absoluteString.contains("releases/tag/v1.9.2"))
    }

    func testManifestWithoutNotes() throws {
        let data = Data(#"{"version":"1.9.2","file":"Light-Stats-1.9.2.dmg"}"#.utf8)
        let release = try XCTUnwrap(ReleaseInfo(manifest: data))
        XCTAssertEqual(release.releaseNotes, "")
        XCTAssertEqual(release.sha256URL?.absoluteString,
                       "https://download.onecat.dev/Light-Stats-1.9.2.dmg.sha256")
    }

    func testManifestPrereleaseVersion() throws {
        let data = Data(#"{"version":"1.9.2-beta.6","file":"Light-Stats-1.9.2-beta.6.dmg"}"#.utf8)
        let release = try XCTUnwrap(ReleaseInfo(manifest: data))
        XCTAssertTrue(release.version.isPrerelease)
        XCTAssertEqual(release.tagName, "v1.9.2-beta.6")
    }

    func testManifestRejectsMissingFile() {
        let data = Data(#"{"version":"1.9.2","file":""}"#.utf8)
        XCTAssertNil(ReleaseInfo(manifest: data))
    }

    func testManifestRejectsBadVersion() {
        let data = Data(#"{"version":"not-a-version","file":"Light-Stats-1.9.2.dmg"}"#.utf8)
        XCTAssertNil(ReleaseInfo(manifest: data))
    }

    func testManifestRejectsMalformedJSON() {
        XCTAssertNil(ReleaseInfo(manifest: Data("not json".utf8)))
    }
}
