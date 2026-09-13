import AppKit
import SwiftUI

struct CleanupPanelHotKeySettingsSection: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        SettingsGroup {
            SettingsRow(
                "settings.cleanupHotKey".localized,
                subtitle: "settings.cleanupHotKey.hint".localized
            ) {
                HStack(spacing: 10) {
                    SettingsToggle(isOn: $settings.cleanupPanelHotKeyEnabled)
                    PanelHotKeyRecorder(
                        selection: $settings.cleanupPanelHotKey,
                        isEnabled: settings.cleanupPanelHotKeyEnabled
                    )
                }
            }
        }
    }
}

private struct PanelHotKeyRecorder: View {
    @Binding var selection: PanelHotKey
    let isEnabled: Bool

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    private static let specialKeyLabels: [UInt16: String] = [
        36: "↩", 76: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 114: "Help", 115: "↖", 116: "⇞", 117: "⌦", 118: "F4",
        119: "↘", 120: "F2", 121: "⇟", 122: "F1", 123: "←", 124: "→",
        125: "↓", 126: "↑"
    ]

    var body: some View {
        Button(action: toggleRecording) {
            Text(isRecording ? "settings.findMouseTriggerKey.recording".localized : selection.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .frame(minWidth: 92)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel("settings.cleanupHotKey".localized)
        .accessibilityValue(selection.displayTitle)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { stopRecording() }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard eventMonitor == nil else { return }
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyDown(event)
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard !event.isARepeat else { return nil }
        if event.keyCode == 53 {
            stopRecording()
            return nil
        }
        let modifiers = eventModifiers(event.modifierFlags)
        guard modifiers != 0 else { return nil }
        selection = PanelHotKey(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            displayKey: keyLabel(for: event)
        )
        stopRecording()
        return nil
    }

    private func eventModifiers(_ flags: NSEvent.ModifierFlags) -> UInt8 {
        var modifiers: UInt8 = 0
        if flags.contains(.control) { modifiers |= PanelHotKey.controlModifier }
        if flags.contains(.option) { modifiers |= PanelHotKey.optionModifier }
        if flags.contains(.shift) { modifiers |= PanelHotKey.shiftModifier }
        if flags.contains(.command) { modifiers |= PanelHotKey.commandModifier }
        return modifiers
    }

    private func keyLabel(for event: NSEvent) -> String {
        if let label = Self.specialKeyLabels[event.keyCode] {
            return label
        }
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            return "⌨︎\(event.keyCode)"
        }
        return characters.uppercased()
    }
}
