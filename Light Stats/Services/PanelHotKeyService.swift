//
//  PanelHotKeyService.swift
//  Light Stats
//
//  Registers one Carbon global hotkey. No Accessibility permission and no CGEventTap.
//

import Carbon
import Foundation
import OSLog

protocol PanelHotKeyControlling: AnyObject {
    var isRunning: Bool { get }
    var onPressed: (() -> Void)? { get set }
    func start(hotKey: PanelHotKey) -> Bool
    func stop()
}

final class PanelHotKeyService: PanelHotKeyControlling {
    private let logger = AppLogger(category: "PanelHotKey")
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var registeredHotKey: PanelHotKey?

    var isRunning: Bool { hotKeyRef != nil }
    var onPressed: (() -> Void)?

    func start(hotKey: PanelHotKey) -> Bool {
        if isRunning, registeredHotKey == hotKey { return true }
        stop()
        guard hotKey.hasModifier else {
            logger.error("Refusing to register a shortcut with no modifiers")
            return false
        }
        guard installHandler() else { return false }

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            Self.carbonModifiers(hotKey.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            logger.error("Failed to register panel hotkey \(hotKey.displayTitle), status=\(status)")
            removeHandler()
            return false
        }
        hotKeyRef = reference
        registeredHotKey = hotKey
        logger.info("Panel hotkey started: \(hotKey.displayTitle)")
        return true
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registeredHotKey = nil
        removeHandler()
        logger.info("Panel hotkey stopped")
    }

    private func installHandler() -> Bool {
        guard eventHandler == nil else { return true }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let service = Unmanaged<PanelHotKeyService>.fromOpaque(userData).takeUnretainedValue()
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
            logger.error("Failed to install panel hotkey handler: \(status)")
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
        guard status == noErr, hotKeyID.signature == Self.signature else { return }
        Task { @MainActor [weak self] in
            self?.onPressed?()
        }
    }

    private static let signature: OSType = 0x4C535048

    static func carbonModifiers(_ modifiers: UInt8) -> UInt32 {
        var result: UInt32 = 0
        if modifiers & PanelHotKey.controlModifier != 0 { result |= UInt32(controlKey) }
        if modifiers & PanelHotKey.optionModifier != 0 { result |= UInt32(optionKey) }
        if modifiers & PanelHotKey.shiftModifier != 0 { result |= UInt32(shiftKey) }
        if modifiers & PanelHotKey.commandModifier != 0 { result |= UInt32(cmdKey) }
        return result
    }
}
