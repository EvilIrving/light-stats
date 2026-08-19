//
//  PerformanceRecordingManager.swift
//  Light Stats
//

import Combine
import Foundation

/// Owns the explicit, persisted 48-hour performance-recording session.
@MainActor
final class PerformanceRecordingManager: ObservableObject {
    nonisolated static let recordingDuration: TimeInterval = 48 * 60 * 60
    nonisolated static let sampleInterval: TimeInterval = 60

    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var endsAt: Date?

    static let shared = PerformanceRecordingManager()

    private enum Key {
        static let sessionID = "performanceRecording.sessionID"
        static let startedAt = "performanceRecording.startedAt"
        static let endsAt = "performanceRecording.endsAt"
    }

    private let defaults: UserDefaults
    private var sessionID: String?
    private var lastSampleAt: Date?

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        let storedSessionID = defaults.string(forKey: Key.sessionID)
        let storedStartedAt = defaults.object(forKey: Key.startedAt) as? Date
        let storedEndsAt = defaults.object(forKey: Key.endsAt) as? Date

        if let storedSessionID, let storedStartedAt, let storedEndsAt, storedEndsAt > now {
            sessionID = storedSessionID
            startedAt = storedStartedAt
            endsAt = storedEndsAt
            isRecording = true
        } else if storedSessionID != nil || storedStartedAt != nil || storedEndsAt != nil {
            clearPersistedSession()
        }
    }

    func start(at date: Date = Date()) {
        guard !isRecording else { return }
        let newSessionID = UUID().uuidString
        let endDate = date.addingTimeInterval(Self.recordingDuration)
        sessionID = newSessionID
        startedAt = date
        endsAt = endDate
        lastSampleAt = nil
        isRecording = true
        defaults.set(newSessionID, forKey: Key.sessionID)
        defaults.set(date, forKey: Key.startedAt)
        defaults.set(endDate, forKey: Key.endsAt)
        recordEvent(action: "started", sessionID: newSessionID, at: date, endsAt: endDate)
    }

    func stop(at date: Date = Date()) {
        finish(action: "stopped", at: date)
    }

    /// Called from the existing system sampling loop. Returning nil keeps the process
    /// sampler entirely off the default path and enforces the one-minute cadence.
    func sessionIDForCapture(at date: Date = Date()) -> String? {
        guard isRecording, let sessionID, let endsAt else { return nil }
        guard date < endsAt else {
            finish(action: "completed", at: date)
            return nil
        }
        if let lastSampleAt, date.timeIntervalSince(lastSampleAt) < Self.sampleInterval {
            return nil
        }
        lastSampleAt = date
        return sessionID
    }

    private func finish(action: String, at date: Date) {
        guard isRecording, let sessionID else { return }
        recordEvent(action: action, sessionID: sessionID, at: date, endsAt: endsAt)
        self.sessionID = nil
        startedAt = nil
        endsAt = nil
        lastSampleAt = nil
        isRecording = false
        clearPersistedSession()
    }

    private func clearPersistedSession() {
        defaults.removeObject(forKey: Key.sessionID)
        defaults.removeObject(forKey: Key.startedAt)
        defaults.removeObject(forKey: Key.endsAt)
    }

    private func recordEvent(action: String, sessionID: String, at date: Date, endsAt: Date?) {
        var fields: [String: DiagnosticLogService.Field] = [
            "session.id": .privateValue(sessionID),
            "session.eventAt": .privateValue(.double(date.timeIntervalSince1970))
        ]
        if let endsAt {
            fields["session.endsAt"] = .privateValue(.double(endsAt.timeIntervalSince1970))
        }
        DiagnosticLogService.recordPerformanceEvent(action: action, fields: fields)
    }
}
