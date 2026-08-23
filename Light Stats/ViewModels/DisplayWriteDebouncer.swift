//
//  DisplayWriteDebouncer.swift
//  Light Stats
//

import Foundation

@MainActor
final class DisplayWriteDebouncer {
    private let delay: Duration
    private var tasks: [UInt32: Task<Void, Never>] = [:]

    init(delay: Duration = .milliseconds(150)) {
        self.delay = delay
    }

    func submit(
        displayID: UInt32,
        value: Double,
        action: @escaping @MainActor (Double) async -> Void
    ) {
        tasks[displayID]?.cancel()
        tasks[displayID] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.delay)
            guard !Task.isCancelled else { return }
            await action(value)
            self.tasks[displayID] = nil
        }
    }

    func cancel(displayID: UInt32) {
        tasks.removeValue(forKey: displayID)?.cancel()
    }

    func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }
}
