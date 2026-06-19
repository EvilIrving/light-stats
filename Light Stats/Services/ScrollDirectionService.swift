//
//  ScrollDirectionService.swift
//  Light Stats
//
//  独立输入设备滚动方向翻转：拦截会话级 CGEventTap，当事件来自传统鼠标滚轮
//  (isContinuous == false) 时翻转垂直滚动方向；触控板/Magic Mouse 直通。
//
//  关键约束：.cgSessionEventTap + .defaultTap 是会话级「主动」tap，WindowServer
//  会同步等待回调返回后才把滚动事件继续派发给任何 App。若 tap 跑在主 RunLoop 上，
//  本 App 每秒的进程扫描 (proc_listallpids + task_info) 会周期性阻塞主线程，期间
//  滚动事件得不到服务 → 整个系统的滚动输入卡死。因此这里把 tap 放到一条专用线程
//  的独立 RunLoop 上运行，与主线程的监控负载彻底解耦。
//

import ApplicationServices
import CoreFoundation
import CoreGraphics
import OSLog

protocol ScrollReversing: AnyObject {
    func checkPermission(promptIfNeeded: Bool) -> Bool
    func start() -> Bool
    func stop()
    var isRunning: Bool { get }
}

/// CGEventTap 管理者：在专用线程的 RunLoop 上持有 tap 与 source，负责事件拦截与
/// delta 翻转。权限检查与提示由调用方（AppDelegate）协调。
final class ScrollDirectionService: ScrollReversing {

    private let logger = Logger(subsystem: "com.lightstats", category: "ScrollDirection")

    // 仅在 tap 线程访问，无需加锁。
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // 跨线程共享，stateLock 守护。
    private let stateLock = NSLock()
    private var running = false
    private var tapRunLoop: CFRunLoop?

    // 仅在主线程（start/stop）访问。
    private var tapThread: Thread?

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running
    }

    func checkPermission(promptIfNeeded: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 启动专用 tap 线程。tap 仅在拥有 Accessibility 权限时创建成功，这里先同步
    /// 确认权限，避免在后台线程才发现失败、还需跨线程回传结果。返回 false 表示
    /// 权限缺失，由调用方决定是否弹窗引导。
    func start() -> Bool {
        guard !isRunning else { return true }
        guard checkPermission(promptIfNeeded: false) else { return false }

        setRunning(true)
        let thread = Thread { [weak self] in self?.runTapLoop() }
        thread.name = "com.lightstats.scroll-direction"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        return true
    }

    func stop() {
        stateLock.lock()
        guard running else { stateLock.unlock(); return }
        running = false
        let loop = tapRunLoop
        stateLock.unlock()

        // 唤醒并停止 tap 线程的 RunLoop；线程在 runTapLoop 尾部自行清理 tap 后退出。
        if let loop {
            CFRunLoopStop(loop)
        }
        tapThread = nil
    }

    // MARK: - Tap Thread

    /// 在专用线程上创建 tap、注册到本线程 RunLoop 并阻塞运行，直到 stop() 触发
    /// CFRunLoopStop。`while isRunning` 兜住「start 后立即 stop」的竞态：若 stop()
    /// 抢先把 running 置 false，循环体不会进入，直接走清理。
    private func runTapLoop() {
        guard let (tap, source) = makeTap() else {
            setRunning(false)
            return
        }

        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        setRunLoop(runLoop)
        logger.info("Scroll direction service started on dedicated thread")

        while isRunning {
            let result = CFRunLoopRunInMode(.defaultMode, 1.0e10, false)
            if result == .stopped { break }
        }

        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        eventTap = nil
        runLoopSource = nil
        setRunLoop(nil)
        logger.info("Scroll direction service stopped")
    }

    private func makeTap() -> (CFMachPort, CFRunLoopSource)? {
        let mask = (1 << CGEventType.scrollWheel.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<ScrollDirectionService>.fromOpaque(refcon).takeUnretainedValue()
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
            logger.error("Failed to create scroll event tap — accessibility permission likely missing")
            return nil
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("Failed to create run loop source for scroll event tap")
            return nil
        }
        return (tap, source)
    }

    // MARK: - Shared State Helpers

    private func setRunning(_ value: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        running = value
    }

    private func setRunLoop(_ loop: CFRunLoop?) {
        stateLock.lock(); defer { stateLock.unlock() }
        tapRunLoop = loop
    }

    // MARK: - Event Handler

    /// 对非连续滚动事件（传统鼠标滚轮）翻转所有纵向 delta 字段，确保不同应用读取
    /// 不同字段时方向一致。连续滚动事件（触控板/Magic Mouse）直通。回调跑在 tap 线程。
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return nil
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard !isContinuous else {
            return Unmanaged.passUnretained(event)
        }

        // 翻转整数像素步进（传统鼠标滚轮的主要载体）
        let dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        if dy != 0 {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -dy)
        }

        // 翻转定点数步进（高分辨率鼠标可能同时设置此字段）
        let fdy = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
        if fdy != 0 {
            event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fdy)
        }

        // 翻转点数步进（部分应用/框架从中读取滚动量）
        let pdy = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        if pdy != 0 {
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pdy)
        }

        return Unmanaged.passUnretained(event)
    }
}
