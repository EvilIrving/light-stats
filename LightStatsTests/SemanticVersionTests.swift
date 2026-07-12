//
//  SemanticVersionTests.swift
//  Light Stats Tests
//
//  Pins SemVer core + prerelease ordering used by the update channel
//  (stable vs beta). Beta bumps like 1.9.0-beta.5 → beta.6 and the
//  promotion beta → final release must sort correctly.
//

import XCTest
@testable import Light_Stats

final class SemanticVersionTests: XCTestCase {

    private func v(_ raw: String) throws -> SemanticVersion {
        try XCTUnwrap(SemanticVersion(raw), "failed to parse \(raw)")
    }

    func testCoreOrdering() throws {
        XCTAssertTrue(try v("1.2.9") < v("1.2.10"))
        XCTAssertTrue(try v("1.8.0") < v("1.9.0"))
        XCTAssertEqual(try v("1.9.0"), try v("v1.9.0"))
    }

    func testPrereleaseLessThanFinal() throws {
        XCTAssertTrue(try v("1.9.0-beta.6") < v("1.9.0"))
        XCTAssertTrue(try v("v1.9.0-beta.1") < v("1.9.0"))
        XCTAssertFalse(try v("1.9.0") < v("1.9.0-beta.6"))
    }

    func testPrereleaseIdentifierOrdering() throws {
        XCTAssertTrue(try v("1.9.0-beta.5") < v("1.9.0-beta.6"))
        XCTAssertTrue(try v("1.9.0-alpha") < v("1.9.0-beta"))
        XCTAssertTrue(try v("1.9.0-beta") < v("1.9.0-beta.1"))
        XCTAssertEqual(try v("1.9.0-beta.6"), try v("v1.9.0-beta.6"))
    }

    func testBuildMetadataIgnored() throws {
        XCTAssertEqual(try v("1.2.3+build.9"), try v("1.2.3"))
        XCTAssertTrue(try v("1.2.3-beta+exp") < v("1.2.3"))
    }

    func testIsPrereleaseFlag() throws {
        XCTAssertTrue(try v("1.9.0-beta.6").isPrerelease)
        XCTAssertFalse(try v("1.9.0").isPrerelease)
    }

    func testReleaseInfoRejectsPrereleaseUnlessAllowed() {
        let jsonString = """
        {
          "tag_name": "v1.9.0-beta.6",
          "body": "notes",
          "html_url": "https://example.com/r",
          "prerelease": true,
          "draft": false,
          "assets": [
            {
              "name": "LightStats.dmg",
              "browser_download_url": "https://example.com/LightStats.dmg"
            }
          ]
        }
        """
        let json = Data(jsonString.utf8)

        XCTAssertNil(ReleaseInfo(json: json), "stable parser must reject prerelease")

        let list = Data("[\(jsonString)]".utf8)
        XCTAssertNil(ReleaseInfo.first(fromListJSON: list, allowPrerelease: false))
        let allowed = ReleaseInfo.first(fromListJSON: list, allowPrerelease: true)
        XCTAssertEqual(allowed?.tagName, "v1.9.0-beta.6")
        XCTAssertTrue(allowed?.version.isPrerelease == true)
    }
}
