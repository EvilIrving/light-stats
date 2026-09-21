//
//  AppLogger.swift
//  Light Stats
//
//  Single logging entry point. Primary sink is the app-owned diagnostic journal
//  (seven-day JSONL under Application Support) for post-hoc investigation.
//  Messages are also handed to os.Logger with private privacy so they can show up
//  in Console after a crash or support session — not for live developer streaming.
//
//  Dedup policy: info/notice/debug collapse identical repeats into one record plus a
//  sparse heartbeat, because a state that stays the same is one fact, not a stream.
//  Errors always write — an error that repeats is exactly what a support report needs.
//

import Foundation
import os

nonisolated struct AppLogger {

    /// Host app OSLog subsystem. Matches `PRODUCT_BUNDLE_IDENTIFIER` so Console
    /// predicates and the process identity stay aligned. One definition for the app.
    static let subsystem = "cain.com.light-stats"

    private let logger: Logger
    private let category: String
    private let mirrorsToJournal: Bool

    init(category: String, mirrorsToJournal: Bool = true) {
        logger = Logger(subsystem: Self.subsystem, category: category)
        self.category = category
        self.mirrorsToJournal = mirrorsToJournal
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .private)")
        recordRepeated(.debug, message)
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .private)")
        recordRepeated(.info, message)
    }

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .private)")
        recordRepeated(.info, message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .private)")
        record(.error, message)
    }

    private func recordRepeated(_ level: DiagnosticLogService.Level, _ message: String) {
        guard mirrorsToJournal else { return }
        DiagnosticLogService.recordRepeatedMessage(level: level, category: category, message: message)
    }

    private func record(_ level: DiagnosticLogService.Level, _ message: String) {
        guard mirrorsToJournal else { return }
        DiagnosticLogService.record(
            level: level,
            category: category,
            action: "message",
            fields: ["message": message]
        )
    }
}
