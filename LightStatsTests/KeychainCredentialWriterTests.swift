//
//  KeychainCredentialWriterTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

final class KeychainCredentialWriterTests: XCTestCase {
    func testQuotesOrdinaryToken() throws {
        let command = try KeychainCredentialWriter.addGenericPasswordCommand(
            account: "ai-usage.deepseek.token",
            secret: "sk-abc"
        )
        XCTAssertTrue(command.contains("-w 'sk-abc'"))
        XCTAssertTrue(command.contains("-U"))
        XCTAssertTrue(command.hasPrefix("add-generic-password"))
    }

    func testQuotesSecretWithSpacesAndQuotes() throws {
        let command = try KeychainCredentialWriter.addGenericPasswordCommand(
            account: "acc",
            secret: "tok with space'and\"slash\\"
        )
        XCTAssertTrue(command.contains("-w 'tok with space'\\''and\"slash\\'"))
    }

    func testRejectsEmptyAndNewlines() {
        XCTAssertThrowsError(
            try KeychainCredentialWriter.addGenericPasswordCommand(account: "a", secret: "")
        ) { error in
            XCTAssertEqual(error as? KeychainCredentialWriter.WriteError, .emptySecret)
        }
        XCTAssertThrowsError(
            try KeychainCredentialWriter.addGenericPasswordCommand(account: "a", secret: "line\nbreak")
        ) { error in
            XCTAssertEqual(error as? KeychainCredentialWriter.WriteError, .controlCharacters)
        }
    }

    func testAccountShape() {
        XCTAssertEqual(
            KeychainCredentialWriter.account(for: .deepseek),
            "ai-usage.deepseek.token"
        )
    }
}
