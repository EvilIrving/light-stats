//
//  AppLogger.swift
//  Light Stats
//
//  Single logging entry point: mirrors human-readable messages to macOS unified
//  logging and the app-owned five-day structured diagnostic journal.
//

import Foundation
import os

nonisolated struct AppLogger {

    private let logger: Logger
    private let category: String
    private let mirrorsToJournal: Bool

    init(subsystem: String, category: String, mirrorsToJournal: Bool = true) {
        logger = Logger(subsystem: subsystem, category: category)
        self.category = category
        self.mirrorsToJournal = mirrorsToJournal
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .private)")
        record(.debug, message)
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .private)")
        record(.info, message)
    }

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .private)")
        record(.warning, message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .private)")
        record(.error, message)
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
