//
//  FindMouseService.swift
//  Light Stats
//
//  Shared pointer gestures on one left modifier: double-tap to dim every
//  display and spotlight the cursor; triple-tap to toggle Presentation Pointer.
//  The event tap is listen-only and never rewrites events.
//

import AppKit
import ApplicationServices
import CoreFoundation
import CoreGraphics
import Foundation
import OSLog

enum FindMouseTriggerAction: Equatable, Sendable {
    case none
    case doubleTapPending(Int)
    case tripleTap
}

/// Shared modifier sequence: two taps schedule Find My Mouse; a quick third tap
/// cancels that pending action and toggles the presentation pointer instead.
struct FindMouseTriggerDetector: Sendable {
    var doubleTapWindow: TimeInterval = 0.5
    var tripleTapWindow: TimeInterval = 0.3
    var retriggerCooldown: TimeInterval = 1.2

    private(set) var lastPressAt: TimeInterval = -.infinity
    private(set) var lastReleaseAt: TimeInterval = -.infinity
    private(set) var lastTriggerAt: TimeInterval = -.infinity
    private var tapCount = 0
    private var nextToken = 0
    private var pendingDoubleToken: Int?

    mutating func registerPress(at now: TimeInterval) -> FindMouseTriggerAction {
        let releasedSincePress = lastReleaseAt > lastPressAt
        let continuationWindow = tapCount == 2 ? tripleTapWindow : doubleTapWindow
        let continuesSequence = releasedSincePress && now - lastPressAt <= continuationWindow
        lastPressAt = now

        guard now - lastTriggerAt >= retriggerCooldown else {
            tapCount = 0
            pendingDoubleToken = nil
            return .none
        }

        tapCount = continuesSequence ? tapCount + 1 : 1
        switch tapCount {
        case 2:
            nextToken += 1
            pendingDoubleToken = nextToken
            return .doubleTapPending(nextToken)
        case 3:
            pendingDoubleToken = nil
            tapCount = 0
            lastTriggerAt = now
            return .tripleTap
        default:
            pendingDoubleToken = nil
            return .none
        }
    }

    mutating func registerRelease(at now: TimeInterval) {
        lastReleaseAt = now
    }

    mutating func commitDoubleTap(token: Int, at now: TimeInterval) -> Bool {
        guard pendingDoubleToken == token, tapCount == 2 else { return false }
        pendingDoubleToken = nil
        tapCount = 0
        lastTriggerAt = now
        return true
    }

    mutating func cancelPendingDoubleTap() {
        pendingDoubleToken = nil
        tapCount = 0
    }

    mutating func reset() {
        lastPressAt = -.infinity
        lastReleaseAt = -.infinity
        lastTriggerAt = -.infinity
        tapCount = 0
        pendingDoubleToken = nil
    }
}

protocol FindMouseControlling: AnyObject {
    var isRunning: Bool { get }
    func start() -> Bool
    func stop()
    func updateTriggerKey(_ key: FindMouseTriggerKey)
}

final class FindMouseService: FindMouseControlling {
    private let logger = AppLogger(category: "FindMouse")
    private let stateLock = NSLock()
    private var running = false
    private var triggerKey: FindMouseTriggerKey = .leftControl
    private var detector = FindMouseTriggerDetector()
    private var spotlightActive = false
    private var lastSpotlightActivityAt: TimeInterval = 0
    private var lastCursorDispatchAt: TimeInterval = 0
    private var idleTimeoutTask: Task<Void, Never>?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let spotlight = FindMouseSpotlightController()
    private let presentationPointer: PresentationPointerControlling

    /// Safety timeout: 4s with no pointer/key/click activity auto-hides.
    private let spotlightIdleTimeout: TimeInterval = 4
    /// Pointer follow is capped at ~60Hz so the main thread is not flooded.
    private let cursorDispatchInterval: TimeInterval = 0.016

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running
    }

    init(presentationPointer: PresentationPointerControlling) {
        self.presentationPointer = presentationPointer
    }

    /// Create the tap on this thread before returning true, matching
    /// `ScrollDirectionService`: a true result means the system accepted
    /// the tap. A rapid stop/start reuses the thread that is still exiting.
    func start() -> Bool {
        guard AccessibilityPermission.isTrusted(prompt: false) else { return false }

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
            newThread.name = "com.lightstats.find-mouse"
            newThread.qualityOfService = .userInteractive
            tapThread = newThread
            thread = newThread
        } else {
            thread = nil
        }
        stateLock.unlock()

        thread?.start()
        return true
    }

    func stop() {
        presentationPointer.stop()
        stateLock.lock()
        guard running else { stateLock.unlock(); return }
        running = false
        detector.reset()
        idleTimeoutTask?.cancel()
        idleTimeoutTask = nil
        let loop = tapRunLoop
        stateLock.unlock()

        dismissSpotlightIfActive()
        if let loop {
            CFRunLoopStop(loop)
        }
    }

    /// Hot-update the trigger key. The tap mask is unchanged, so the tap
    /// does not need to restart.
    func updateTriggerKey(_ key: FindMouseTriggerKey) {
        stateLock.lock()
        triggerKey = key
        detector.reset()
        stateLock.unlock()
    }

    // MARK: - Event tap

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
        Task { @MainActor [weak self] in
            self?.presentationPointer.stop()
        }
        logger.info("Find-my-mouse service stopped")
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
        logger.info("Find-my-mouse service started")

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
        // flagsChanged detects the double-tap; mouseMoved follows the
        // pointer; keys/clicks dismiss. All listen-only.
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<FindMouseService>.fromOpaque(refcon).takeUnretainedValue()
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
            logger.error("Failed to create find-mouse event tap")
            return nil
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("Failed to create run loop source for find-mouse tap")
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

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stateLock.lock()
            detector.reset()
            stateLock.unlock()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .mouseMoved:
            handleMouseMoved()
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            cancelPendingDoubleTap()
            dismissSpotlightIfActive()
        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        stateLock.lock()
        let key = triggerKey
        stateLock.unlock()
        guard keyCode == key.keyCode else { return }

        let isPress: Bool
        switch key {
        case .leftControl: isPress = event.flags.contains(.maskControl)
        case .leftOption: isPress = event.flags.contains(.maskAlternate)
        case .leftCommand: isPress = event.flags.contains(.maskCommand)
        case .leftShift: isPress = event.flags.contains(.maskShift)
        }

        let now = ProcessInfo.processInfo.systemUptime
        if isPress {
            stateLock.lock()
            let action = detector.registerPress(at: now)
            stateLock.unlock()
            handleTriggerAction(action)
        } else {
            stateLock.lock()
            detector.registerRelease(at: now)
            stateLock.unlock()
        }
    }

    private func handleTriggerAction(_ action: FindMouseTriggerAction) {
        switch action {
        case .none:
            break
        case .doubleTapPending(let token):
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.commitDoubleTap(token: token)
            }
        case .tripleTap:
            dismissSpotlightIfActive()
            Task { @MainActor [weak self] in
                self?.togglePresentationPointer()
            }
        }
    }

    private func commitDoubleTap(token: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        let triggered = detector.commitDoubleTap(token: token, at: now)
        let alreadyActive = spotlightActive
        if triggered, !alreadyActive {
            spotlightActive = true
            lastSpotlightActivityAt = now
        }
        stateLock.unlock()
        guard triggered, !alreadyActive else { return }
        Task { @MainActor [weak self] in
            self?.showSpotlight()
        }
    }

    private func cancelPendingDoubleTap() {
        stateLock.lock()
        detector.cancelPendingDoubleTap()
        stateLock.unlock()
    }

    @MainActor
    private func togglePresentationPointer() {
        if presentationPointer.isRunning {
            presentationPointer.stop()
        } else {
            presentationPointer.start()
        }
    }

    private func handleMouseMoved() {
        stateLock.lock()
        let active = spotlightActive
        let now = ProcessInfo.processInfo.systemUptime
        let shouldDispatch = active && now - lastCursorDispatchAt >= cursorDispatchInterval
        if shouldDispatch {
            lastCursorDispatchAt = now
            lastSpotlightActivityAt = now
        }
        stateLock.unlock()
        guard shouldDispatch else { return }
        Task { @MainActor [weak self] in
            self?.spotlight.updateCursor()
        }
    }

    private func dismissSpotlightIfActive() {
        stateLock.lock()
        let wasActive = spotlightActive
        if wasActive {
            spotlightActive = false
        }
        stateLock.unlock()
        guard wasActive else { return }
        Task { @MainActor [weak self] in
            self?.spotlight.hide()
        }
    }

    @MainActor
    private func showSpotlight() {
        spotlight.show()
        scheduleSpotlightIdleTimeout()
    }

    /// Idle poll every 0.5s. Pointer motion refreshes the timestamp; 4s
    /// of stillness hides the overlay. Rebuilt on each show so a rapid
    /// retrigger does not stack pollers. Locking stays in sync helpers
    /// so the async task never calls `NSLock` directly.
    private func scheduleSpotlightIdleTimeout() {
        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                guard self.shouldIdleDismiss() else { continue }
                self.dismissSpotlightIfActive()
                return
            }
        }
        replaceIdleTimeoutTask(task)
    }

    private func shouldIdleDismiss() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        defer { stateLock.unlock() }
        guard spotlightActive else { return false }
        return now - lastSpotlightActivityAt >= spotlightIdleTimeout
    }

    private func replaceIdleTimeoutTask(_ task: Task<Void, Never>) {
        stateLock.lock()
        idleTimeoutTask?.cancel()
        idleTimeoutTask = task
        stateLock.unlock()
    }
}

// MARK: - Spotlight overlay

/// One borderless overlay per display: full-screen dim with an even-odd
/// hole at the pointer. The window ignores mouse events.
@MainActor
private final class FindMouseSpotlightController {
    static let spotlightRadius: CGFloat = 84
    private static let dimAlpha: CGFloat = 0.72

    private var windows: [NSWindow] = []

    func show() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let view = SpotlightDimView(radius: Self.spotlightRadius, dimAlpha: Self.dimAlpha)
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = view
            window.alphaValue = 0
            window.orderFrontRegardless()
            return window
        }
        updateCursor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            windows.forEach { $0.animator().alphaValue = 1 }
        }
    }

    func updateCursor() {
        let point = NSEvent.mouseLocation
        for window in windows {
            guard let view = window.contentView as? SpotlightDimView else { continue }
            let frame = window.frame
            view.spotlightCenter = CGPoint(
                x: point.x - frame.minX,
                y: point.y - frame.minY
            )
            view.needsDisplay = true
        }
    }

    func hide() {
        let fading = windows
        windows = []
        guard !fading.isEmpty else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fading.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            fading.forEach { $0.orderOut(nil) }
        })
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            fading.forEach { $0.orderOut(nil) }
        }
    }
}

/// Dim view: translucent black over the display, with an even-odd hole
/// at the pointer so the real screen shows through.
private final class SpotlightDimView: NSView {
    var spotlightCenter: CGPoint?

    private let radius: CGFloat
    private let dimAlpha: CGFloat

    init(radius: CGFloat, dimAlpha: CGFloat) {
        self.radius = radius
        self.dimAlpha = dimAlpha
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SpotlightDimView is created in code only")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        if let center = spotlightCenter {
            let hole = NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            if hole.intersects(bounds) {
                path.append(NSBezierPath(ovalIn: hole))
                path.windingRule = .evenOdd
            }
        }
        NSColor.black.withAlphaComponent(dimAlpha).setFill()
        path.fill()
    }
}
