//
//  KeyComboRecorder.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// Records a key combination into a Carbon key code plus modifier mask.
///
/// Generalised from the cleanup panel's recorder, which was the only place in the project that
/// already did this. Wins uses the `KeyboardShortcuts` package; a third-party dependency is not
/// worth adding for forty lines that already exist here, but the *behaviour* is what matters and it
/// is now shared: click to record, Escape cancels, and the button always shows what is bound.
struct KeyComboRecorder: View {

    let keyCode: UInt32
    let modifiers: UInt32
    var onRecord: (UInt32, UInt32) -> Void
    /// Clears the binding instead of recording a new one. `nil` hides the clear affordance, which
    /// is right for bindings that must always exist.
    var onClear: (() -> Void)?
    /// Shown when there is no binding yet.
    var emptyTitle: String = "settings.shortcut.none".localized

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleRecording) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 84)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .onDisappear(perform: stopRecording)

            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("settings.shortcut.clear".localized)
            }
        }
    }

    private var title: String {
        if isRecording { return "settings.findMouseTriggerKey.recording".localized }
        guard keyCode != 0 || modifiers != 0 else { return emptyTitle }
        return WindowSnapKeyCode.displayTitle(keyCode: keyCode, modifiers: modifiers)
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
        if event.keyCode == UInt16(WindowSnapKeyCode.escape) {
            stopRecording()
            return nil
        }

        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        // A bare key is not a global shortcut; requiring a modifier is what keeps the recorder from
        // swallowing ordinary typing.
        guard modifiers != 0 else { return nil }

        onRecord(UInt32(event.keyCode), modifiers)
        stopRecording()
        return nil
    }

    /// Carbon modifier masks from AppKit flags. Carbon's ordering (`⌃⌥⇧⌘`) is what the label
    /// renders, and the values are the ones `RegisterEventHotKey` expects.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= WindowSnapKeyCode.control }
        if flags.contains(.option) { result |= WindowSnapKeyCode.option }
        if flags.contains(.shift) { result |= WindowSnapKeyCode.shift }
        if flags.contains(.command) { result |= WindowSnapKeyCode.command }
        return result
    }
}
