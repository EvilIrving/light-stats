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

    /// CGEventType 未包含 NX_SYSDEFINED (14)，用 raw value 直接构造。
    private static let nxSystemDefined = CGEventType(rawValue: 14)!

    private let logger = AppLogger(category: "KeyboardLock")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func checkPermission(promptIfNeeded: Bool) -> Bool {
        AccessibilityPermission.isTrusted(prompt: promptIfNeeded)
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }

        // keyDown/keyUp 覆盖标准按键；flagsChanged 覆盖修饰键；
        // systemDefined 覆盖媒体键/亮度/音量等顶层功能键（NX_SYSDEFINED 事件）。
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << Self.nxSystemDefined.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
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
        // 先清空实例变量，防止 disable 触发的 .tapDisabledByTimeout
        // 回调重新启用 tap（否则 tap 启用但无 runLoop source，键盘会卡死）。
        let tap = eventTap
        let source = runLoopSource
        eventTap = nil
        runLoopSource = nil

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }

    /// 吞掉所有键盘事件；系统因超时/用户输入临时禁用 tap 时立即重新启用，
    /// 否则键盘会在锁定期间中途恢复响应。
    ///
    /// systemDefined（NX_SYSDEFINED）不做 subtype 过滤，全量吞掉，
    /// 避免媒体键/亮度/音量/电源键等因 subtype 差异被漏过。
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return nil
        }

        if type == Self.nxSystemDefined {
            return nil
        }

        return nil
    }
}
