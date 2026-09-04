import AppKit
import SwiftUI

struct FindMouseTriggerRecorder: View {
    @Binding var selection: FindMouseTriggerKey
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
            Text(isRecording ? "settings.findMouseTriggerKey.recording".localized : displayTitle)
                .font(.system(size: 12, weight: .medium))
                .frame(minWidth: 92)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel("settings.findMouseTriggerKey".localized)
        .accessibilityValue(displayTitle)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { stopRecording() }
        }
        .onDisappear(perform: stopRecording)
    }

    private var displayTitle: String {
        if let isLeft = selection.isLeftModifier {
            let side = isLeft
                ? "settings.findMouseTriggerKey.left".localized
                : "settings.findMouseTriggerKey.right".localized
            return "\(side) \(selection.displayKey)"
        }
        if selection.isModifierOnly {
            return selection.displayKey
        }
        return selection.modifierSymbols + selection.displayKey
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
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            switch event.type {
            case .flagsChanged:
                recordModifier(event)
            case .keyDown:
                recordShortcut(event)
            default:
                break
            }
            return event
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }

    private func recordModifier(_ event: NSEvent) {
        guard let key = FindMouseTriggerKey.modifierKey(keyCode: Int64(event.keyCode)),
              eventModifiers(event.modifierFlags) & key.modifiers != 0 else { return }
        selection = key
        stopRecording()
    }

    private func recordShortcut(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        selection = FindMouseTriggerKey(
            keyCode: Int64(event.keyCode),
            modifiers: eventModifiers(event.modifierFlags),
            displayKey: keyLabel(for: event)
        )
        stopRecording()
    }

    private func eventModifiers(_ flags: NSEvent.ModifierFlags) -> UInt8 {
        var modifiers: UInt8 = 0
        if flags.contains(.control) { modifiers |= FindMouseTriggerKey.controlModifier }
        if flags.contains(.option) { modifiers |= FindMouseTriggerKey.optionModifier }
        if flags.contains(.shift) { modifiers |= FindMouseTriggerKey.shiftModifier }
        if flags.contains(.command) { modifiers |= FindMouseTriggerKey.commandModifier }
        if flags.contains(.function) { modifiers |= FindMouseTriggerKey.functionModifier }
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
