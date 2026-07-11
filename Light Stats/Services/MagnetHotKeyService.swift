//
//  MagnetHotKeyService.swift
//  Light Stats
//
//  Registers Magnet-style global shortcuts and routes them to WindowSnappingService.
//

import Carbon
import Foundation
import OSLog

protocol MagnetHotKeyControlling: AnyObject {
    var isRunning: Bool { get }
    func start() -> Bool
    func stop()
}

final class MagnetHotKeyService: MagnetHotKeyControlling {
    private struct Registration {
        var reference: EventHotKeyRef
        var action: WindowSnapAction
    }

    private let logger = AppLogger(subsystem: "com.lightstats", category: "MagnetHotKeys")
    private let snappingService: WindowSnappingService
    private var registrations: [UInt32: Registration] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextIdentifier: UInt32 = 1

    var isRunning: Bool { !registrations.isEmpty }

    init(snappingService: WindowSnappingService) {
        self.snappingService = snappingService
    }

    func start() -> Bool {
        guard !isRunning else { return true }
        guard snappingService.checkPermission(promptIfNeeded: false) else { return false }
        guard installHandler() else { return false }

        for hotKey in Self.defaultHotKeys {
            register(hotKey)
        }

        if registrations.isEmpty {
            removeHandler()
            return false
        }
        logger.info("Magnet hotkeys started with \(self.registrations.count) registrations")
        return true
    }

    func stop() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        registrations.removeAll()
        removeHandler()
        logger.info("Magnet hotkeys stopped")
    }

    private func installHandler() -> Bool {
        guard eventHandler == nil else { return true }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let service = Unmanaged<MagnetHotKeyService>.fromOpaque(userData).takeUnretainedValue()
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

    private func register(_ hotKey: WindowSnapHotKey) {
        let identifier = nextIdentifier
        nextIdentifier += 1

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            logger.debug("Failed to register hotkey \(hotKey.keyCode), status=\(status)")
            return
        }
        registrations[identifier] = Registration(reference: reference, action: hotKey.action)
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
              let action = registrations[hotKeyID.id]?.action else {
            return
        }
        snappingService.perform(action)
    }

    private static let signature: OSType = 0x4C53574B

    private static let baseModifiers = UInt32(controlKey | optionKey)

    static let defaultHotKeys: [WindowSnapHotKey] = [
        WindowSnapHotKey(keyCode: UInt32(kVK_LeftArrow), modifiers: baseModifiers, action: .leftHalf),
        WindowSnapHotKey(keyCode: UInt32(kVK_RightArrow), modifiers: baseModifiers, action: .rightHalf),
        WindowSnapHotKey(keyCode: UInt32(kVK_UpArrow), modifiers: baseModifiers, action: .topHalf),
        WindowSnapHotKey(keyCode: UInt32(kVK_DownArrow), modifiers: baseModifiers, action: .bottomHalf)
    ]
}
