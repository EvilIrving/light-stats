//
//  WindowVisibilityService.swift
//  Light Stats
//

import AppKit
import OSLog

/// Hides and restores other applications.
///
/// Uses `NSRunningApplication.hide()` rather than minimizing windows one by one. That is the same
/// path the Dock's "Hide Others" (⌥⌘H) takes, so the behaviour is the one macOS already documents —
/// and it works on applications whose Accessibility tree is unusable, which is exactly the set a
/// window-by-window implementation would fail on.
///
/// It only ever un-hides what it hid. Restoring every hidden application would bring back windows
/// the user had hidden themselves, which is the kind of "helpful" that loses trust.
nonisolated final class WindowVisibilityService: @unchecked Sendable {

    private let logger = AppLogger(category: "WindowVisibility")
    private let stateLock = NSLock()
    private var hiddenProcessIDs: Set<pid_t> = []

    var hiddenCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return hiddenProcessIDs.count
    }

    /// Hides every other application, keeping `processID` visible.
    @discardableResult
    func hideOthers(keeping processID: pid_t?) -> Int {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return hide { application in
            application.processIdentifier != ownPID && application.processIdentifier != processID
        }
    }

    /// Hides every application, including the one that asked.
    @discardableResult
    func hideAll() -> Int {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return hide { $0.processIdentifier != ownPID }
    }

    /// Brings back exactly the applications this service hid.
    @discardableResult
    func restore() -> Int {
        stateLock.lock()
        let processIDs = hiddenProcessIDs
        hiddenProcessIDs.removeAll()
        stateLock.unlock()

        var restored = 0
        for processID in processIDs {
            guard let application = NSRunningApplication(processIdentifier: processID) else { continue }
            if application.unhide() {
                restored += 1
            }
        }
        logger.info("Restored \(restored) of \(processIDs.count) hidden applications")
        DiagnosticLogService.record(
            category: "windowManagement",
            action: "visibilityRestored",
            fields: ["restored": String(restored), "tracked": String(processIDs.count)]
        )
        return restored
    }

    /// Forgets what was hidden without un-hiding it. Used when window management is switched off,
    /// where restoring would be a surprise the user did not ask for.
    func forgetHistory() {
        stateLock.lock()
        hiddenProcessIDs.removeAll()
        stateLock.unlock()
    }

    private func hide(where shouldHide: (NSRunningApplication) -> Bool) -> Int {
        var hidden: Set<pid_t> = []
        for application in NSWorkspace.shared.runningApplications {
            // Only regular apps can be hidden. Accessories and background-only processes ignore the
            // request, and counting them would make "restore" wait on applications that never left.
            guard application.activationPolicy == .regular,
                  !application.isHidden,
                  shouldHide(application) else { continue }
            if application.hide() {
                hidden.insert(application.processIdentifier)
            }
        }

        stateLock.lock()
        hiddenProcessIDs.formUnion(hidden)
        let total = hiddenProcessIDs.count
        stateLock.unlock()

        logger.info("Hid \(hidden.count) applications, tracking \(total)")
        DiagnosticLogService.record(
            category: "windowManagement",
            action: "visibilityHidden",
            fields: ["hidden": String(hidden.count), "tracked": String(total)]
        )
        return hidden.count
    }
}
