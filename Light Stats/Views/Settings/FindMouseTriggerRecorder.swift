import AppKit
import SwiftUI

struct FindMouseTriggerRecorder: View {
    @Binding var selection: FindMouseTriggerKey
    let isEnabled: Bool

    @State private var isRecording = false
    @State private var eventMonitor: Any?

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
        switch event.keyCode {
        case 36, 76: return "↩"
        case 48: return "⇥"
        case 49: return "␣"
        case 51: return "⌫"
        case 53: return "⎋"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "↖"
        case 116: return "⇞"
        case 117: return "⌦"
        case 118: return "F4"
        case 119: return "↘"
        case 120: return "F2"
        case 121: return "⇟"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
                return "⌨︎\(event.keyCode)"
            }
            return characters.uppercased()
        }
    }
}
