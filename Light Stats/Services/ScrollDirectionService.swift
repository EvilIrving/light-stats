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

/// 滚动处理参数。仅作用于传统鼠标滚轮事件；垂直/水平反转互相独立，步长倍率
/// 同时缩放两个轴的滚动像素量。
struct ScrollConfig: Sendable, Equatable {
    var reverseVertical: Bool
    var reverseHorizontal: Bool
    var stepMultiplier: Double

    static let identity = ScrollConfig(reverseVertical: false, reverseHorizontal: false, stepMultiplier: 1.0)
}

protocol ScrollReversing: AnyObject {
    func checkPermission(promptIfNeeded: Bool) -> Bool
    func start() -> Bool
    func stop()
    func updateConfig(_ config: ScrollConfig)
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
    private var config = ScrollConfig.identity

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

    /// 由调用方（AppDelegate）在设置变更时调用，热更新处理参数；无需重启 tap。
    func updateConfig(_ newConfig: ScrollConfig) {
        stateLock.lock(); defer { stateLock.unlock() }
        config = newConfig
    }

    private func currentConfig() -> ScrollConfig {
        stateLock.lock(); defer { stateLock.unlock() }
        return config
    }

    // MARK: - Event Handler

    /// 对非连续滚动事件（传统鼠标滚轮）按当前配置翻转方向并缩放步长。连续滚动事件
    /// （触控板/Magic Mouse）直通。回调跑在 tap 线程，配置经 stateLock 读取快照。
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

        let cfg = currentConfig()
        applyAxis(event, vertical: true, reverse: cfg.reverseVertical, multiplier: cfg.stepMultiplier)
        applyAxis(event, vertical: false, reverse: cfg.reverseHorizontal, multiplier: cfg.stepMultiplier)
        return Unmanaged.passUnretained(event)
    }

    /// 对单个滚动轴的三个 delta 字段（整数行步进、定点数、点数）统一施加「翻转 × 倍率」。
    /// 不同应用读取不同字段，全部处理以保证行为一致。
    private func applyAxis(_ event: CGEvent, vertical: Bool, reverse: Bool, multiplier: Double) {
        let factor = (reverse ? -1.0 : 1.0) * multiplier
        guard factor != 1.0 else { return } // 既不翻转也不缩放：原样放行

        let lineField: CGEventField = vertical ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2
        let fixedField: CGEventField = vertical ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2
        let pointField: CGEventField = vertical ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventPointDeltaAxis2

        // 整数行步进量化为整数：缩放后若舍入为 0 但原值非 0，保留结果方向的最小 ±1，
        // 否则按行滚动的应用会在低倍率下完全失去滚动。
        scaleField(event, lineField, by: factor, keepDirectionFloor: true)
        scaleField(event, fixedField, by: factor, keepDirectionFloor: false)
        scaleField(event, pointField, by: factor, keepDirectionFloor: false)
    }

    private func scaleField(_ event: CGEvent, _ field: CGEventField, by factor: Double, keepDirectionFloor: Bool) {
        let raw = event.getIntegerValueField(field)
        guard raw != 0 else { return }

        let product = Double(raw) * factor
        var scaled = Int64(product.rounded())
        if keepDirectionFloor && scaled == 0 {
            scaled = product > 0 ? 1 : -1
        }
        event.setIntegerValueField(field, value: scaled)
    }
}
