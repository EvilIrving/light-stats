//
//  PerformanceRecordingSettingsRow.swift
//  Light Stats
//

import SwiftUI

struct PerformanceRecordingSettingsRow: View {
    @ObservedObject private var recording = PerformanceRecordingManager.shared

    var body: some View {
        SettingsRow(
            "settings.performanceRecording".localized,
            subtitle: subtitle
        ) {
            Button(buttonTitle) {
                if recording.isRecording {
                    recording.stop()
                } else {
                    recording.start()
                }
            }
            .controlSize(.regular)
        }
    }

    private var subtitle: String {
        guard recording.isRecording, let endsAt = recording.endsAt else {
            return "settings.performanceRecording.hint".localized
        }
        let endText = endsAt.formatted(date: .abbreviated, time: .shortened)
        return "settings.performanceRecording.active".localized(endText)
    }

    private var buttonTitle: String {
        (recording.isRecording
            ? "settings.performanceRecording.stop"
            : "settings.performanceRecording.start").localized
    }
}
