//
//  ScrollDirectionService.swift
//  Light Stats
//
//  独立输入设备滚动方向翻转：拦截会话级 CGEventTap，当事件来自传统鼠标滚轮
//  (isContinuous == false) 时翻转滚动方向并缩放步长；触控板/Magic Mouse 直通。
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

    static let identity = ScrollConfig(reverseVertical: false, reverseHorizontal: false, stepMultiplier: 1.0)
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

    private let logger = Logger(subsystem: "com.lightstats", category: "ScrollDirection")

    // 仅在 tap 线程访问，无需加锁。
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // 跨线程共享，stateLock 守护。
    private let stateLock = NSLock()
    private var running = false
    private var suspended = false
    private var tapRunLoop: CFRunLoop?
    private var config = ScrollConfig.identity

    // 仅在主线程（start/stop）访问。
    private var tapThread: Thread?

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running
    }

    func checkPermission(promptIfNeeded: Bool) -> Bool {
        AccessibilityPermission.isTrusted(prompt: promptIfNeeded)
    }

    // MARK: - Lifecycle

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

    func setSuspended(_ suspended: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        self.suspended = suspended
    }

    private func currentState() -> (config: ScrollConfig, suspended: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        return (config, suspended)
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

        let state = currentState()
        guard !state.suspended else {
            return Unmanaged.passUnretained(event)
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let cfg = state.config
        // 各轴的有符号乘数：翻转贡献 -1，步长倍率同时缩放两轴。等于 1 即原样放行。
        let vmul = (cfg.reverseVertical ? -1.0 : 1.0) * cfg.stepMultiplier
        let hmul = (cfg.reverseHorizontal ? -1.0 : 1.0) * cfg.stepMultiplier

        guard !isContinuous else {
            return Unmanaged.passUnretained(event)
        }
        guard vmul != 1.0 || hmul != 1.0 else {
            return Unmanaged.passUnretained(event)
        }

        // 关键：所有原始值必须在写任何字段之前一次性读完。设置 DeltaAxis 会让 macOS
        // 按固定倍率重算 FixedPt/PointDelta，若边读边写，后续字段读到的是「重算后」的值，
        // ×乘数会把方向二次翻转回原样（先前终端方向不翻、浏览器却正常的根因）。
        let vSample = sampleAxis(event, fields: Self.verticalFields)
        let hSample = sampleAxis(event, fields: Self.horizontalFields)
        let hidBefore = CGEventCopyIOHIDEvent(event)?.takeRetainedValue()
        let origHidY = hidBefore.map { IOHIDEventGetFloatValue($0, kIOHIDEventFieldScrollY) } ?? 0
        let origHidX = hidBefore.map { IOHIDEventGetFloatValue($0, kIOHIDEventFieldScrollX) } ?? 0

        // 用原始值写回 CGEvent 三个 delta 字段（行步进 → 定点数 → 点数）。
        if vmul != 1.0 { writeAxis(event, fields: Self.verticalFields, sample: vSample, factor: vmul) }
        if hmul != 1.0 { writeAxis(event, fields: Self.horizontalFields, sample: hSample, factor: hmul) }

        // 改完 CGEvent 后「重新」拷贝一份 IOHID 写入反转值。改 CGEvent 会让系统重建底层
        // IOHIDEvent，沿用旧拷贝写入会落在已脱钩对象上而失效，故此处取新鲜拷贝。
        let hidAfter = CGEventCopyIOHIDEvent(event)?.takeRetainedValue()
        if let hidAfter {
            if vmul != 1.0 { IOHIDEventSetFloatValue(hidAfter, kIOHIDEventFieldScrollY, origHidY * vmul) }
            if hmul != 1.0 { IOHIDEventSetFloatValue(hidAfter, kIOHIDEventFieldScrollX, origHidX * hmul) }
        }
        return Unmanaged.passUnretained(event)
    }

    /// 一次性读取单轴三个 delta 字段的原始值（写任何字段之前调用）。
    private func sampleAxis(_ event: CGEvent, fields: AxisFields) -> AxisSample {
        AxisSample(
            line: event.getIntegerValueField(fields.line),
            fixed: event.getDoubleValueField(fields.fixed),
            point: event.getIntegerValueField(fields.point)
        )
    }

    /// 用预读的原始值写回单轴三个 delta 字段，施加「翻转 × 倍率」。顺序 行步进 → 定点数
    /// → 点数：先写 DeltaAxis 触发系统重算，随后的定点/点数写入再覆盖回正确反转值。
    private func writeAxis(_ event: CGEvent, fields: AxisFields, sample: AxisSample, factor: Double) {
        // 整数行步进：缩放后若舍入为 0 但原值非 0，保留结果方向的最小 ±1，
        // 否则按行滚动的应用会在低倍率下完全失去滚动。
        if sample.line != 0 {
            let product = Double(sample.line) * factor
            var scaled = Int64(product.rounded())
            if scaled == 0 { scaled = product > 0 ? 1 : -1 }
            event.setIntegerValueField(fields.line, value: scaled)
        }
        // 定点数是亚整数浮点值（如 0.3）：必须走 Double 接口，整数接口会截断为 0。
        if sample.fixed != 0 {
            event.setDoubleValueField(fields.fixed, value: sample.fixed * factor)
        }
        if sample.point != 0 {
            event.setIntegerValueField(fields.point, value: Int64((Double(sample.point) * factor).rounded()))
        }
    }
}
