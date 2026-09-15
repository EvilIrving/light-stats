//
//  WindowControlService.swift
//  Light Stats
//

import AppKit
import ApplicationServices

nonisolated enum WindowControlService {
    static func canPerform(_ action: WindowSnapAction, processID: pid_t) -> Bool {
        guard action.isWindowControl, processID != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: processID),
              app.activationPolicy == .regular, !app.isTerminated else { return false }
        if action == .quitApplication { return true }
        return AXCommandQueue.shared.sync { focusedWindow(processID) != nil }
    }

    static func perform(_ action: WindowSnapAction, processID: pid_t) -> Bool {
        guard canPerform(action, processID: processID),
              let app = NSRunningApplication(processIdentifier: processID) else { return false }
        if action == .quitApplication { return app.terminate() }
        return AXCommandQueue.shared.sync {
            guard let window = focusedWindow(processID) else { return false }
            app.activate()
            return WindowListService.close(element: window)
        }
    }

    private static func focusedWindow(_ processID: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(processID)
        return AXElementReader.attribute(kAXFocusedWindowAttribute, from: app)
            ?? AXElementReader.attribute(kAXMainWindowAttribute, from: app)
    }
}
