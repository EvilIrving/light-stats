//
//  SnapConfigurationBox.swift
//  Light Stats
//

import Foundation

/// A configuration reader that can be used from any thread.
///
/// The drag pipeline reads the configuration from its event-tap thread and from the AX queue, while
/// the settings live on the main actor. This box is the single hand-off: everything else about the
/// configuration (which field means what) stays in `SnapConfiguration`.
nonisolated final class SnapConfigurationBox: @unchecked Sendable {

    private let lock = NSLock()
    private var value: SnapConfiguration

    init(_ configuration: SnapConfiguration = .default) {
        value = configuration
    }

    func update(_ configuration: SnapConfiguration) {
        lock.lock()
        value = configuration
        lock.unlock()
    }

    func current() -> SnapConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
