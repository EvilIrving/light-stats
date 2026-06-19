//
//  TitlebarGestureService.swift
//  Light Stats
//
//  Observes continuous scroll gestures and converts deliberate titlebar swipes
//  into window snapping actions. The event tap is listen-only and does not run
//  Accessibility queries inside the tap callback.
//

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
    private struct GestureState {
        var deltaX: Double = 0
        var deltaY: Double = 0
        var lastEventAt: TimeInterval = 0
        var lastTriggeredAt: TimeInterval = 0
    }

    private let logger = Logger(subsystem: "com.lightstats", category: "TitlebarGestures")
    private let snappingService: WindowSnappingService
    private let stateLock = NSLock()
    private var running = false
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureState = GestureState()

    private let threshold: Double = 36
    private let dominanceRatio: Double = 1.45
    private let resetInterval: TimeInterval = 0.25
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
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard isContinuous else { return }

        let point = event.location
        let deltaY = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        let deltaX = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        guard deltaX != 0 || deltaY != 0 else { return }

        if let action = registerGesture(deltaX: deltaX, deltaY: deltaY) {
            Task { [weak self] in
                self?.snappingService.perform(action, at: point)
            }
        }
    }

    private func registerGesture(deltaX: Double, deltaY: Double) -> WindowSnapAction? {
        let now = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        defer { stateLock.unlock() }

        if now - gestureState.lastEventAt > resetInterval {
            gestureState.deltaX = 0
            gestureState.deltaY = 0
        }
        gestureState.lastEventAt = now
        gestureState.deltaX += deltaX
        gestureState.deltaY += deltaY

        guard now - gestureState.lastTriggeredAt >= triggerCooldown else { return nil }
        let action = dominantAction(deltaX: gestureState.deltaX, deltaY: gestureState.deltaY)
        if action != nil {
            gestureState.deltaX = 0
            gestureState.deltaY = 0
            gestureState.lastTriggeredAt = now
        }
        return action
    }

    private func dominantAction(deltaX: Double, deltaY: Double) -> WindowSnapAction? {
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
}
