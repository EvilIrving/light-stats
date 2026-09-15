//
//  WindowSnapHotKeyService.swift
//  Light Stats
//
//  Registers global snap shortcuts and routes them to WindowSnappingService.
//

import Carbon
import Foundation
import OSLog

protocol WindowSnapHotKeyControlling: AnyObject {
    var isRunning: Bool { get }
    /// Registers the given set. Idempotent for an unchanged set, so a settings change that does not
    /// touch the shortcuts does not tear the registrations down and build them again.
    @discardableResult
    func start(shortcuts: [SnapShortcut]) -> Bool
    func stop()
}

/// Registers the user's snap shortcuts with Carbon.
///
/// The set is data (`SnapConfiguration.shortcuts`), not a `static let`. That is the whole point of
/// the rewrite: the previous fixed six bindings meant 13 of the 19 actions could only be reached by
/// clicking a menu bar item, and a user could not rebind even those six.
final class WindowSnapHotKeyService: WindowSnapHotKeyControlling {

    private struct Registration {
        var reference: EventHotKeyRef
        var target: SnapTarget
    }

    private let logger = AppLogger(category: "WindowSnapHotKeys")
    private let snappingService: WindowSnappingService
    private var registrations: [UInt32: Registration] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextIdentifier: UInt32 = 1
    /// The exact set that is currently registered, so a redundant restart can be skipped.
    private var registeredShortcuts: [SnapShortcut] = []

    var isRunning: Bool { !registrations.isEmpty }

    init(snappingService: WindowSnappingService) {
        self.snappingService = snappingService
    }

    /// Registers every enabled shortcut in `shortcuts`. Returns `false` only when nothing could be
    /// registered at all, so a single taken binding cannot take the whole feature down.
    @discardableResult
    func start(shortcuts: [SnapShortcut]) -> Bool {
        if isRunning, registeredShortcuts == shortcuts { return true }
        stop()

        guard snappingService.checkPermission(promptIfNeeded: false) else { return false }
        guard installHandler() else { return false }

        let enabled = shortcuts.filter(\.isBound)
        for shortcut in enabled {
            register(shortcut)
        }
        registeredShortcuts = shortcuts

        if enabled.isEmpty {
            logger.info("No snap shortcuts configured")
            return false
        }
        if registrations.count != enabled.count {
            let failed = enabled.count - registrations.count
            logger.error("Failed to register \(failed) of \(enabled.count) window shortcuts")
            DiagnosticLogService.record(
                level: .error,
                category: "windowManagement",
                action: "shortcutsPartial",
                fields: ["registered": String(registrations.count), "requested": String(enabled.count)]
            )
        }
        logger.info("Window snap hotkeys started with \(self.registrations.count) registrations")
        return true
    }

    func stop() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        registrations.removeAll()
        registeredShortcuts = []
        removeHandler()
        logger.info("Window snap hotkeys stopped")
    }

    private func installHandler() -> Bool {
        guard eventHandler == nil else { return true }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let service = Unmanaged<WindowSnapHotKeyService>.fromOpaque(userData).takeUnretainedValue()
            service.handle(event: event)
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            logger.error("Failed to install hotkey event handler: \(status)")
            return false
        }
        return true
    }

    private func removeHandler() {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func register(_ shortcut: SnapShortcut) {
        let identifier = nextIdentifier
        nextIdentifier += 1

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            logger.debug("Failed to register hotkey \(shortcut.keyCode), status=\(status)")
            return
        }
        registrations[identifier] = Registration(reference: reference, target: shortcut.target)
    }

    private func handle(event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == Self.signature,
              let target = registrations[hotKeyID.id]?.target else {
            return
        }
        snappingService.perform(target)
    }

    private static let signature: OSType = 0x4C53574B
}
