//
//  TitlebarGestureService.swift
//  Light Stats
//
//  Observes continuous scroll gestures and converts deliberate titlebar swipes
//  into window snapping actions. The event tap is listen-only and does not run
//  Accessibility queries inside the tap callback.
//

import AppKit
import ApplicationServices
import CoreFoundation
import CoreGraphics
import Foundation
import OSLog

protocol TitlebarGestureControlling: AnyObject {
    var isRunning: Bool { get }
    func start() -> Bool
    func stop()
}

final class TitlebarGestureService: TitlebarGestureControlling {
    private enum GestureEvent {
        case threshold(WindowSnapAction, CGPoint)
        case ready(WindowSnapAction, CGPoint)
        case commit(WindowSnapAction, CGPoint)
        case cancel
    }

    private struct GestureState {
        var deltaX: Double = 0
        var deltaY: Double = 0
        var thresholdAction: WindowSnapAction?
        var readyAction: WindowSnapAction?
        var lastPoint: CGPoint?
        var lastEventAt: TimeInterval = 0
        var lastTriggeredAt: TimeInterval = 0
    }

    private let logger = Logger(subsystem: "com.lightstats", category: "TitlebarGestures")
    private let snappingService: WindowSnappingService
    private let previewService = WindowSnapPreviewService()
    private let stateLock = NSLock()
    private var running = false
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureState = GestureState()
    private var previewTimeoutTask: Task<Void, Never>?
    private var previewToken: UInt64 = 0

    private let resistanceThreshold: Double = 20
    private let hapticThreshold: Double = 40
    private let completionThreshold: Double = 60
    private let dominanceRatio: Double = 1.45
    private let resetInterval: TimeInterval = 0.9
    private let previewIdleTimeout: TimeInterval = 0.45
    private let triggerCooldown: TimeInterval = 0.55

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running
    }

    init(snappingService: WindowSnappingService) {
        self.snappingService = snappingService
    }

    func start() -> Bool {
        guard !isRunning else { return true }
        guard snappingService.checkPermission(promptIfNeeded: false) else { return false }

        setRunning(true)
        let thread = Thread { [weak self] in self?.runTapLoop() }
        thread.name = "com.lightstats.titlebar-gestures"
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

        cancelPreviewTimeout()
        invalidatePreviewToken()
        hidePreview()

        if let loop {
            CFRunLoopStop(loop)
        }
        tapThread = nil
    }

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
        logger.info("Titlebar gesture service started")

        while isRunning {
            let result = CFRunLoopRunInMode(.defaultMode, 1.0e10, false)
            if result == .stopped { break }
        }

        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        eventTap = nil
        runLoopSource = nil
        setRunLoop(nil)
        logger.info("Titlebar gesture service stopped")
    }

    private func makeTap() -> (CFMachPort, CFRunLoopSource)? {
        let mask = (1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<TitlebarGestureService>.fromOpaque(refcon).takeUnretainedValue()
            service.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Failed to create titlebar gesture event tap")
            return nil
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("Failed to create run loop source for titlebar gesture tap")
            return nil
        }
        return (tap, source)
    }

    private func setRunning(_ value: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        running = value
    }

    private func setRunLoop(_ loop: CFRunLoop?) {
        stateLock.lock(); defer { stateLock.unlock() }
        tapRunLoop = loop
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetGestureAndHidePreview()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard isContinuous else { return }

        if isReleaseEvent(event) {
            handleGestureEvent(releaseGesture())
            return
        }

        let point = event.location
        let deltaY = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        let deltaX = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        guard deltaX != 0 || deltaY != 0 else { return }

        let gestureEvent = registerGesture(deltaX: deltaX, deltaY: deltaY, point: point)
        if gestureEvent == nil && hasActivePreviewGesture() {
            schedulePreviewTimeout()
        }
        handleGestureEvent(gestureEvent)
    }

    private func handleGestureEvent(_ event: GestureEvent?) {
        switch event {
        case .threshold(let action, let point):
            schedulePreviewTimeout()
            showPreview(for: action, at: point, feedback: true)
        case .ready(let action, let point):
            schedulePreviewTimeout()
            showPreview(for: action, at: point)
        case .commit(let action, let point):
            cancelPreviewTimeout()
            hidePreview()
            Task { [weak self] in
                self?.snappingService.perform(action, at: point)
            }
        case .cancel:
            cancelPreviewTimeout()
            hidePreview()
        case nil:
            break
        }
    }

    private func registerGesture(deltaX: Double, deltaY: Double, point: CGPoint) -> GestureEvent? {
        let now = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        defer { stateLock.unlock() }

        if now - gestureState.lastEventAt > resetInterval {
            let shouldCancel = gestureState.thresholdAction != nil || gestureState.readyAction != nil
            gestureState = GestureState()
            if shouldCancel {
                previewToken += 1
                return .cancel
            }
        }
        gestureState.lastEventAt = now
        gestureState.deltaX += deltaX
        gestureState.deltaY += deltaY
        gestureState.lastPoint = point

        guard dominantAction(deltaX: gestureState.deltaX, deltaY: gestureState.deltaY, threshold: resistanceThreshold) != nil else {
            return nil
        }

        if let action = dominantAction(deltaX: gestureState.deltaX, deltaY: gestureState.deltaY, threshold: hapticThreshold),
           gestureState.thresholdAction != action {
            gestureState.thresholdAction = action
            return .threshold(action, point)
        }

        guard now - gestureState.lastTriggeredAt >= triggerCooldown else { return nil }
        guard let action = dominantAction(
            deltaX: gestureState.deltaX,
            deltaY: gestureState.deltaY,
            threshold: completionThreshold
        ) else {
            return nil
        }

        if gestureState.readyAction != action {
            gestureState.readyAction = action
            return .ready(action, point)
        }
        return nil
    }

    private func hasActivePreviewGesture() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return gestureState.thresholdAction != nil || gestureState.readyAction != nil
    }

    private func releaseGesture() -> GestureEvent? {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard let point = gestureState.lastPoint else { return nil }
        if let action = gestureState.readyAction {
            gestureState = GestureState(lastEventAt: ProcessInfo.processInfo.systemUptime)
            previewToken += 1
            return .commit(action, point)
        }
        if gestureState.thresholdAction != nil {
            gestureState = GestureState(lastEventAt: ProcessInfo.processInfo.systemUptime)
            previewToken += 1
            return .cancel
        }
        gestureState = GestureState()
        return nil
    }

    private func isReleaseEvent(_ event: CGEvent) -> Bool {
        let endedOrCancelledMask: Int64 = 0x1C
        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        return scrollPhase & endedOrCancelledMask != 0 || momentumPhase & endedOrCancelledMask != 0
    }

    private func dominantAction(deltaX: Double, deltaY: Double, threshold: Double) -> WindowSnapAction? {
        let absX = abs(deltaX)
        let absY = abs(deltaY)

        if absX >= threshold && absX >= absY * dominanceRatio {
            return deltaX > 0 ? .rightHalf : .leftHalf
        }
        if absY >= threshold && absY >= absX * dominanceRatio {
            return deltaY > 0 ? .minimize : .maximize
        }
        return nil
    }

    private func showPreview(for action: WindowSnapAction, at point: CGPoint, feedback: Bool = false) {
        let token = currentPreviewToken()
        Task { @MainActor [weak self] in
            guard let self, isPreviewTokenCurrent(token) else { return }
            guard let frame = snappingService.previewFrame(for: action, at: point) else {
                if isPreviewTokenCurrent(token) {
                    previewService.hide()
                }
                return
            }
            guard isPreviewTokenCurrent(token) else { return }
            if feedback {
                performElasticThresholdFeedback()
            }
            previewService.show(frame: frame)
        }
    }

    private func currentPreviewToken() -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return previewToken
    }

    private func isPreviewTokenCurrent(_ token: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return previewToken == token
    }

    private func invalidatePreviewToken() {
        stateLock.lock()
        previewToken += 1
        gestureState = GestureState()
        stateLock.unlock()
    }

    private func resetGestureAndHidePreview() {
        cancelPreviewTimeout()
        invalidatePreviewToken()
        hidePreview()
    }

    private func schedulePreviewTimeout() {
        let context = previewContext()
        let timeout = UInt64(previewIdleTimeout * 1_000_000_000)
        stateLock.lock()
        previewTimeoutTask?.cancel()
        previewTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled else { return }
            self?.cancelIdlePreview(lastEventAt: context.lastEventAt, token: context.token)
        }
        stateLock.unlock()
    }

    private func previewContext() -> (lastEventAt: TimeInterval, token: UInt64) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (gestureState.lastEventAt, previewToken)
    }

    private func cancelPreviewTimeout() {
        stateLock.lock()
        previewTimeoutTask?.cancel()
        previewTimeoutTask = nil
        stateLock.unlock()
    }

    private func cancelIdlePreview(lastEventAt: TimeInterval, token: UInt64) {
        stateLock.lock()
        let shouldCancel = previewToken == token
            && gestureState.lastEventAt == lastEventAt
            && (gestureState.thresholdAction != nil || gestureState.readyAction != nil)
        if shouldCancel {
            previewToken += 1
            gestureState = GestureState()
            previewTimeoutTask = nil
        }
        stateLock.unlock()
        if shouldCancel {
            hidePreview()
        }
    }

    private func hidePreview() {
        Task { @MainActor [weak self] in
            self?.previewService.hide()
        }
    }

    private func performElasticThresholdFeedback() {
        Task { @MainActor in
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }
}
