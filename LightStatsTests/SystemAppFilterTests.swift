//
//  SystemAppFilterTests.swift
//  Light Stats Tests
//
//  Guards the system-app watch-list matching, in particular that it is
//  case-insensitive — macOS bundle IDs don't distinguish case, so a casing typo
//  in the list (e.g. "com.apple.appstore" vs the real "com.apple.AppStore")
//  must not drop the app from the cleanup view.
//

import XCTest
@testable import Light_Stats

final class SystemAppFilterTests: XCTestCase {

    func testAppStoreMatchesDespiteListCasing() {
        // Real bundle ID is com.apple.AppStore; the list entry is lowercased.
        XCTAssertTrue(isSystemAppInWatchList("com.apple.AppStore"))
        XCTAssertTrue(isSystemAppInWatchList("com.apple.appstore"))
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertTrue(isSystemAppInWatchList("com.apple.safari"))
        XCTAssertTrue(isSystemAppInWatchList("COM.APPLE.SAFARI"))
        XCTAssertTrue(isSystemAppInWatchList("com.apple.Music"))
    }

    func testNonWatchedAndEmptyAreExcluded() {
        XCTAssertFalse(isSystemAppInWatchList("com.example.someapp"))
        XCTAssertFalse(isSystemAppInWatchList(""))
        XCTAssertFalse(isSystemAppInWatchList(nil))
    }
}
