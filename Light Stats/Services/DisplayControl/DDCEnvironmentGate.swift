//
//  DDCEnvironmentGate.swift
//  Light Stats
//

import AppKit
import CoreGraphics
import Foundation

nonisolated final class DDCEnvironmentGate: @unchecked Sendable {
    private let wakeDelay: TimeInterval
    private let reconfigureDelay: TimeInterval
    private let reconfigureSafetyDelay: TimeInterval
    private let lock = NSLock()

    private var asleep = false
    private var suppressedUntil: Date?

    private var observers: [NSObjectProtocol] = []
    private var changeTask: Task<Void, Never>?
    private var changeHandler: (@MainActor () -> Void)?
    private var isStarted = false

    init(
        wakeDelay: TimeInterval = 3,
        reconfigureDelay: TimeInterval = 1,
        reconfigureSafetyDelay: TimeInterval = 5
    ) {
        self.wakeDelay = wakeDelay
        self.reconfigureDelay = reconfigureDelay
        self.reconfigureSafetyDelay = reconfigureSafetyDelay
    }

    var isSuppressed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return asleep || suppressedUntil.map { Date() < $0 } == true
    }

    @MainActor
    func start(onChange: @escaping @MainActor () -> Void) {
        changeHandler = onChange
        guard !isStarted else { return }
        isStarted = true

        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.handleWillSleep()
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.handleDidWake()
            }
        ]

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let result = CGDisplayRegisterReconfigurationCallback(Self.reconfigurationCallback, pointer)
        if result != .success {
            AppLogger(category: "DisplayControl").error("Failed to register display reconfiguration callback: \(result)")
        }
    }

    @MainActor
    func stop() {
        guard isStarted else { return }
        isStarted = false
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        changeTask?.cancel()
        changeTask = nil
        changeHandler = nil

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRemoveReconfigurationCallback(Self.reconfigurationCallback, pointer)
        updateSuppression(asleep: false, until: nil)
    }

    func handleWillSleep() {
        updateSuppression(asleep: true, until: nil)
    }

    func handleDidWake() {
        updateSuppression(asleep: false, until: Date().addingTimeInterval(wakeDelay))
        scheduleChangeFromAnyThread(after: wakeDelay + 0.3)
    }

    func handleReconfigure(flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.beginConfigurationFlag) {
            updateSuppression(
                asleep: nil,
                until: Date().addingTimeInterval(reconfigureSafetyDelay)
            )
            return
        }

        updateSuppression(
            asleep: nil,
            until: Date().addingTimeInterval(reconfigureDelay)
        )
        scheduleChangeFromAnyThread(after: reconfigureDelay + 0.2)
    }

    private func scheduleChangeFromAnyThread(after delay: TimeInterval) {
        Task { @MainActor [weak self] in
            self?.scheduleChange(after: delay)
        }
    }

    private func updateSuppression(asleep: Bool?, until: Date?) {
        lock.lock()
        if let asleep {
            self.asleep = asleep
        }
        suppressedUntil = until
        lock.unlock()
    }

    @MainActor
    private func scheduleChange(after delay: TimeInterval) {
        changeTask?.cancel()
        changeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.changeHandler?()
        }
    }

    nonisolated private static let reconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, context in
        guard let context else { return }
        let gate = Unmanaged<DDCEnvironmentGate>.fromOpaque(context).takeUnretainedValue()
        gate.handleReconfigure(flags: flags)
    }
}
