//
//  KeyboardLockService.swift
//  Light Stats
//
//  清洁模式：用 CGEventTap 在系统级吞掉键盘事件。只管权限检测与 tap 生命周期，
//  不创建任何 UI（遮罩窗口由 View 层负责）。
//

import ApplicationServices
import CoreFoundation
import CoreGraphics
import OSLog

protocol KeyboardLocking: AnyObject {
    func checkPermission(promptIfNeeded: Bool) -> Bool
    func start() -> Bool
    func stop()
}

/// CGEvent.tapCreate 的回调跑在创建 tap 时所在线程的 RunLoop 上，不天然适配 actor 隔离，
/// 因此这里用普通 class，由调用方（@MainActor 的 ViewModel）保证单线程调用。
final class KeyboardLockService: KeyboardLocking {

    private let logger = Logger(subsystem: "com.lightstats", category: "KeyboardLock")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func checkPermission(promptIfNeeded: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let service = Unmanaged<KeyboardLockService>.fromOpaque(refcon).takeUnretainedValue()
            return service.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Failed to create keyboard event tap")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// 吞掉所有目标事件；系统因超时/用户输入临时禁用 tap 时立即重新启用，
    /// 否则键盘会在锁定期间中途恢复响应。
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return nil
        }
        return nil
    }
}
