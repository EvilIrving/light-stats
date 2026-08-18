//
//  ScrollDirectionService.swift
//  Light Stats
//
//  独立输入设备滚动方向翻转：拦截会话级 CGEventTap。传统鼠标滚轮（离散事件）可
//  翻转垂直/水平方向、缩放步长、关闭滚动加速度（每次固定 N 行）；触控板/Magic Mouse
//  （连续事件）默认直通，可选一并反转方向。
//
//  关键：macOS 开启 Natural Scrolling 后，方向的「权威来源」是事件底层的
//  IOHIDEvent 浮点值，而非 CGEvent 的 delta 字段。仅改 CGEvent 字段会被系统
//  从 IOHIDEvent 重新派生覆盖、方向翻不动。因此必须经 CGEventCopyIOHIDEvent()
//  取出底层 IOHIDEvent，改写其 ScrollX/ScrollY 浮点值（方案参考 Scroll
//  Reverser 1.8.2 的 MouseTap.m）。CGEvent 的三个 delta 字段同步改写，兼容
//  直接读 CGEvent 的应用。
//
//  ABI 关键：64 位 Mac 上 IOHIDFloat 是 double，IOHIDEventGet/SetFloatValue
//  必须按 Double 声明——按 Float 声明会取到错位的垃圾值，方向静默失效。
//
//  时序关键（两条，缺一则部分应用方向错乱，详细踩坑记录见 sessionlog.md）：
//  1) 所有原始 delta 必须在写任何字段之前一次性读完。先写 DeltaAxis 会让系统按固定
//     倍率重算 FixedPt/PointDelta；若边读边写，后续字段读到重算值，×乘数后方向被二次
//     翻转回原样（曾导致终端方向不翻、浏览器却正常）。
//  2) 改完 CGEvent 字段后必须「重新」CGEventCopyIOHIDEvent 再写 IOHID。改 CGEvent 会
//     重建底层 IOHIDEvent，沿用改之前的旧拷贝写入会落在已脱钩对象上而失效。
//
//  关键约束：.cgSessionEventTap + .defaultTap 是会话级「主动」tap，WindowServer
//  会同步等待回调返回后才把滚动事件继续派发给任何 App。若回调阻塞，全系统滚动
//  输入冻结。因此 tap 跑在专用线程的独立 RunLoop 上，回调全程无 I/O、无日志、
//  无危险 SPI；并与主线程每秒的进程扫描负载彻底解耦。
//

import AppKit
import ApplicationServices
import CoreFoundation
import CoreGraphics
import OSLog

// MARK: - IOHIDEvent Bridge (private SPI)

/// IOHIDEvent scroll 字段索引。kIOHIDEventTypeScroll = 6，base = 6 << 16。
private let kIOHIDEventFieldScrollX: UInt32 = 0x0006_0000
private let kIOHIDEventFieldScrollY: UInt32 = 0x0006_0001

/// `CGEventCopyIOHIDEvent` —— 返回 CGEvent 底层的 IOHIDEvent（Copy 语义，+1 引用）。
/// 取回后用 `takeRetainedValue()` 交给 ARC 释放，不会过度释放。
@_silgen_name("CGEventCopyIOHIDEvent")
private func CGEventCopyIOHIDEvent(_ event: CGEvent?) -> Unmanaged<CFTypeRef>?

/// `IOHIDEventGetFloatValue` —— 读 IOHIDEvent 浮点字段。IOHIDFloat 在 64 位上是 double。
@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: UInt32) -> Double

/// `IOHIDEventSetFloatValue` —— 写 IOHIDEvent 浮点字段。
@_silgen_name("IOHIDEventSetFloatValue")
private func IOHIDEventSetFloatValue(_ event: CFTypeRef, _ field: UInt32, _ value: Double)

// MARK: - Config & Protocol

/// 滚动处理参数。仅作用于传统鼠标滚轮事件；垂直/水平反转互相独立，步长倍率
/// 同时缩放两个轴的滚动像素量。
struct ScrollConfig: Sendable, Equatable {
    var reverseVertical: Bool
    var reverseHorizontal: Bool
    var stepMultiplier: Double
    /// 关闭鼠标滚轮加速度：开启后每次滚轮事件滚动固定 `scrollLines` 行，滚动量不再随转速放大。
    var disableAcceleration: Bool
    /// 加速度关闭时每次滚轮事件滚动的行数（1–10，默认 3）。仅在 disableAcceleration 开启时生效。
    var scrollLines: Int
    /// 触控板 / Magic Mouse（连续滚动事件）是否也参与方向反转。默认 false：仅传统鼠标滚轮。
    var includeTrackpad: Bool

    /// 是否有任一功能需要挂载事件 tap。
    var isActive: Bool { reverseVertical || reverseHorizontal || disableAcceleration }

    static let identity = ScrollConfig(
        reverseVertical: false, reverseHorizontal: false, stepMultiplier: 1.0,
        disableAcceleration: false, scrollLines: 3, includeTrackpad: false
    )
}

protocol ScrollReversing: AnyObject {
    func checkPermission(promptIfNeeded: Bool) -> Bool
    func start() -> Bool
    func stop()
    func setSuspended(_ suspended: Bool)
    func updateConfig(_ config: ScrollConfig)
    var isRunning: Bool { get }
}

// MARK: - Service

/// CGEventTap 管理者：在专用线程的 RunLoop 上持有 tap 与 source，负责事件拦截与
/// 方向/倍率变换。权限检查与提示由调用方（AppDelegate）协调。
final class ScrollDirectionService: ScrollReversing {

    /// 单个滚动轴的 CGEvent 三个 delta 字段。IOHID 字段不在此处——其拷贝时机特殊
    /// （须在改完 CGEvent 后重新拷贝），故在 handle 中直接用常量处理。
    private struct AxisFields {
        let line: CGEventField     // 整数行步进
        let fixed: CGEventField    // 定点浮点数
        let point: CGEventField    // 整数点数
    }

    /// 单轴三个 delta 字段的原始读数快照（写入前一次性采集，避免读到系统重算值）。
    private struct AxisSample {
        let line: Int64
        let fixed: Double
        let point: Int64
    }

    private static let verticalFields = AxisFields(
        line: .scrollWheelEventDeltaAxis1,
        fixed: .scrollWheelEventFixedPtDeltaAxis1,
        point: .scrollWheelEventPointDeltaAxis1
    )

    private static let horizontalFields = AxisFields(
        line: .scrollWheelEventDeltaAxis2,
        fixed: .scrollWheelEventFixedPtDeltaAxis2,
        point: .scrollWheelEventPointDeltaAxis2
    )

    private let logger = AppLogger(category: "ScrollDirection")

    // 仅在 tap 线程访问，无需加锁。
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // 跨线程共享，stateLock 守护。
    private let stateLock = NSLock()
    private var running = false
    private var suspended = false
    private var tapRunLoop: CFRunLoop?
    private var config = ScrollConfig.identity

    // stateLock 守护；start 创建，tap 线程退出前清空。
    private var tapThread: Thread?
    private var wakeObserver: NSObjectProtocol?
    private var wakeRecoveryTask: Task<Void, Never>?

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running
    }

    func checkPermission(promptIfNeeded: Bool) -> Bool {
        AccessibilityPermission.isTrusted(prompt: promptIfNeeded)
    }

    // MARK: - Lifecycle

    /// 启动专用 tap 线程。首次启动时先同步创建 tap，确保返回 true 时系统已经接受
    /// tap，而不是仅表示后台线程已提交。快速 stop/start 则复用尚在退出的线程重建。
    func start() -> Bool {
        guard checkPermission(promptIfNeeded: false) else { return false }

        stateLock.lock()
        if running {
            stateLock.unlock()
            return true
        }
        let needsThread = tapThread == nil
        stateLock.unlock()

        let initialSession: (CFMachPort, CFRunLoopSource)?
        if needsThread {
            guard let session = makeTap() else { return false }
            initialSession = session
        } else {
            initialSession = nil
        }

        stateLock.lock()
        running = true
        let thread: Thread?
        if tapThread == nil {
            let newThread = Thread { [weak self] in
                self?.runTapLoop(initialSession: initialSession)
            }
            newThread.name = "com.lightstats.scroll-direction"
            newThread.qualityOfService = .userInteractive
            tapThread = newThread
            thread = newThread
        } else {
            // stop() 后立即重新开启时，复用尚在退出过程中的线程，由其重建 tap。
            thread = nil
        }
        stateLock.unlock()

        registerForWakeNotifications()
        thread?.start()
        return true
    }

    func stop() {
        removeWakeObserver()
        stateLock.lock()
        guard running else { stateLock.unlock(); return }
        running = false
        let loop = tapRunLoop
        stateLock.unlock()

        // 唤醒并停止当前 tap session；线程完成清理后退出，或在快速重新开启时重建 tap。
        if let loop {
            CFRunLoopStop(loop)
        }
    }

    private func registerForWakeNotifications() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestTapRecovery()
            self?.wakeRecoveryTask?.cancel()
            self?.wakeRecoveryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.requestTapRecovery()
            }
        }
    }

    private func removeWakeObserver() {
        wakeRecoveryTask?.cancel()
        wakeRecoveryTask = nil
        guard let wakeObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        self.wakeObserver = nil
    }

    // MARK: - Tap Thread

    /// 在专用线程上创建 tap 并运行。tap 在睡眠后失效时结束当前 session 并在同一线程
    /// 重建；stop() 后若设置被立即重新开启，也复用该线程，避免旧新 tap 并存。
    private func runTapLoop(initialSession: (CFMachPort, CFRunLoopSource)? = nil) {
        var pendingSession = initialSession
        while prepareTapSession() {
            let session = pendingSession ?? makeTap()
            pendingSession = nil
            guard let (tap, source) = session else {
                setRunning(false)
                continue
            }
            runTapSession(tap: tap, source: source)
        }
        logger.info("Scroll direction service stopped")
    }

    private func prepareTapSession() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard running else {
            tapThread = nil
            return false
        }
        return true
    }

    private func runTapSession(tap: CFMachPort, source: CFRunLoopSource) {
        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        setRunLoop(runLoop)
        logger.info("Scroll direction service started on dedicated thread")

        while isRunning {
            let result = CFRunLoopRunInMode(.defaultMode, 1.0e10, false)
            if result == .stopped || result == .finished { break }
        }

        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        eventTap = nil
        runLoopSource = nil
        setRunLoop(nil)
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
            logger.error("System rejected creation of the scroll event tap")
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

    /// 睡眠唤醒后 HID 子系统可能短暂禁用 tap。在 tap 自己的 RunLoop 上恢复，避免从
    /// 主线程并发访问 CFMachPort；延迟的第二次恢复由 wake observer 覆盖 HID 就绪竞态。
    private func requestTapRecovery() {
        stateLock.lock()
        let isRunning = running
        let loop = isRunning ? tapRunLoop : nil
        stateLock.unlock()

        if !isRunning {
            // 第一次恢复若恰逢 HID 尚未就绪而重建失败，唤醒后的延迟重试从这里再启动。
            _ = start()
            return
        }
        guard let loop else { return }

        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            self?.reEnableTapIfNeeded()
        }
        CFRunLoopWakeUp(loop)
    }

    private func reEnableTapIfNeeded() {
        guard let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        if !CGEvent.tapIsEnabled(tap: eventTap) {
            // standby 可能直接使 port 失效；结束当前 session，由 runTapLoop 重新创建。
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    /// 由调用方（AppDelegate）在设置变更时调用，热更新处理参数；无需重启 tap。
    func updateConfig(_ newConfig: ScrollConfig) {
        stateLock.lock(); defer { stateLock.unlock() }
        config = newConfig
    }

    func setSuspended(_ suspended: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        self.suspended = suspended
    }

    private func currentState() -> (config: ScrollConfig, suspended: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        return (config, suspended)
    }

    // MARK: - Event Handler

    /// 对滚动事件按当前配置翻转方向、缩放步长，并可选关闭滚轮加速度。离散滚轮
    /// 事件始终处理；连续事件（触控板/Magic Mouse）仅在 includeTrackpad 开启时处理。
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reEnableTapIfNeeded()
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

        let state = currentState()
        guard !state.suspended else {
            return Unmanaged.passUnretained(event)
        }

        let cfg = state.config
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0

        // 触控板 / Magic Mouse 是连续滚动事件。默认直通（保持系统自然滚动）；仅当
        // includeTrackpad 打开时才参与方向反转。连续事件无离散「格」概念，不做加速度归一化。
        if isContinuous && !cfg.includeTrackpad {
            return Unmanaged.passUnretained(event)
        }

        // 连续设备只参与方向反转；步长倍率依附于至少一个滚轮反转开关。关闭加速度时，
        // 固定行数独立于倍率，但 point/fixed/IOHID 仍保留已启用反转的像素步长语义。
        let hasReversal = cfg.reverseVertical || cfg.reverseHorizontal
        let stepMultiplier = !isContinuous && hasReversal ? cfg.stepMultiplier : 1.0
        let verticalDirection = cfg.reverseVertical ? -1.0 : 1.0
        let horizontalDirection = cfg.reverseHorizontal ? -1.0 : 1.0
        let vmul = verticalDirection * stepMultiplier
        let hmul = horizontalDirection * stepMultiplier
        let normalizeVertical = cfg.disableAcceleration && !isContinuous

        guard vmul != 1.0 || hmul != 1.0 || normalizeVertical else {
            return Unmanaged.passUnretained(event)
        }

        // 关键：所有原始值必须在写任何字段之前一次性读完。设置 DeltaAxis 会让 macOS
        // 按固定倍率重算 FixedPt/PointDelta，若边读边写，后续字段读到的是「重算后」的值，
        // ×乘数会把方向二次翻转回原样（先前终端方向不翻、浏览器却正常的根因）。
        let vSample = sampleAxis(event, fields: Self.verticalFields)
        let hSample = sampleAxis(event, fields: Self.horizontalFields)

        // 关闭加速度时只归一化垂直 DeltaAxis1，与两个参考实现一致。固定行数是独立
        // 参数，不再叠乘 stepMultiplier；point/fixed/IOHID 仍只做方向与像素倍率变换。
        let vLine = lineFactor(
            sample: vSample,
            direction: verticalDirection,
            scrollLines: cfg.scrollLines,
            normalize: normalizeVertical,
            fallback: vmul
        )
        let hLine = hmul
        let changesEvent = vLine != 1.0 || hLine != 1.0 || vmul != 1.0 || hmul != 1.0
        let hidBefore = changesEvent ? CGEventCopyIOHIDEvent(event)?.takeRetainedValue() : nil
        let origHidY = hidBefore.map { IOHIDEventGetFloatValue($0, kIOHIDEventFieldScrollY) } ?? 0
        let origHidX = hidBefore.map { IOHIDEventGetFloatValue($0, kIOHIDEventFieldScrollX) } ?? 0

        // 用预读的原始值写回 CGEvent 字段（行步进 → 定点数 → 点数）。
        writeAxis(event, fields: Self.verticalFields, sample: vSample, lineFactor: vLine, rawFactor: vmul)
        writeAxis(event, fields: Self.horizontalFields, sample: hSample, lineFactor: hLine, rawFactor: hmul)

        // 改完 CGEvent 后「重新」拷贝一份 IOHID 写入原始值 × 方向/倍率。即使只改
        // DeltaAxis1，也必须恢复两个 HID 轴，避免系统重建事件后不同字段语义分叉。
        let hidAfter = changesEvent ? CGEventCopyIOHIDEvent(event)?.takeRetainedValue() : nil
        if let hidAfter {
            IOHIDEventSetFloatValue(hidAfter, kIOHIDEventFieldScrollY, origHidY * vmul)
            IOHIDEventSetFloatValue(hidAfter, kIOHIDEventFieldScrollX, origHidX * hmul)
        }
        return Unmanaged.passUnretained(event)
    }

    /// 关闭加速度时将非零垂直行步进归一化为固定 `scrollLines`，仅额外施加方向。
    /// `fallback` 用于未归一化路径，包含离散滚轮的方向与步长倍率。
    private func lineFactor(
        sample: AxisSample,
        direction: Double,
        scrollLines: Int,
        normalize: Bool,
        fallback: Double
    ) -> Double {
        guard normalize, sample.line != 0, scrollLines > 0 else { return fallback }
        return (Double(scrollLines) / Double(abs(sample.line))) * direction
    }

    /// 一次性读取单轴三个 delta 字段的原始值（写任何字段之前调用）。
    private func sampleAxis(_ event: CGEvent, fields: AxisFields) -> AxisSample {
        AxisSample(
            line: event.getIntegerValueField(fields.line),
            fixed: event.getDoubleValueField(fields.fixed),
            point: event.getIntegerValueField(fields.point)
        )
    }

    /// 用预读的原始值写回单轴三个 delta 字段。顺序 行步进 → 定点数 → 点数：先写 DeltaAxis
    /// 触发系统重算，随后的定点/点数写入再覆盖回原始值 × 方向/倍率。只归一化行步进时也
    /// 必须恢复 fixed/point（包括零值），否则不同 App 读取不同字段会得到不一致的滚动量。
    private func writeAxis(_ event: CGEvent, fields: AxisFields, sample: AxisSample, lineFactor: Double, rawFactor: Double) {
        let lineChanged = sample.line != 0 && lineFactor != 1.0
        if lineChanged {
            event.setIntegerValueField(fields.line, value: scaledInteger(sample.line, by: lineFactor))
        }
        guard lineChanged || rawFactor != 1.0 else { return }

        // 定点数是亚整数浮点值（如 0.3）：必须走 Double 接口，整数接口会截断为 0。
        event.setDoubleValueField(fields.fixed, value: sample.fixed * rawFactor)
        event.setIntegerValueField(fields.point, value: scaledInteger(sample.point, by: rawFactor))
    }

    /// 低倍率下整数 delta 可能舍入成 0；保留变换后符号的最小单位，避免部分 App 丢滚动。
    private func scaledInteger(_ value: Int64, by factor: Double) -> Int64 {
        let product = Double(value) * factor
        let scaled = Int64(product.rounded())
        guard scaled == 0, product != 0 else { return scaled }
        return product > 0 ? 1 : -1
    }
}
