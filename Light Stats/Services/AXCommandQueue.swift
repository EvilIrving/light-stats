//
//  AXCommandQueue.swift
//  Light Stats
//

import Foundation
import OSLog

/// Serialises Accessibility calls.
///
/// Accessibility is effectively serial per application: two concurrent requests to the same app
/// block each other, and a blocked request that is waiting on a menu-bar press can hold the caller
/// for seconds. Wins discovered the same thing and funnels every AX call through one dedicated
/// queue (`accessibilityCommandsQueue`, with a note that it "waits synchronously before return").
///
/// The drag pipeline and the placement engine share this queue, so a drag can never be starved by
/// a burst of window reads, and a window read can never interleave with a frame write.
final class AXCommandQueue {

    static let shared = AXCommandQueue()

    private let queue = DispatchQueue(
        label: "com.lightstats.accessibility-commands",
        qos: .userInteractive
    )
    /// Identifies the queue so `sync` can refuse a nested call instead of deadlocking.
    private let key = DispatchSpecificKey<UInt8>()

    init() {
        queue.setSpecific(key: key, value: 1)
    }

    /// Runs `work` on the AX queue and waits for the result.
    ///
    /// Refuses to run when already on the queue: `DispatchQueue.sync` from within the same queue is
    /// an immediate deadlock, and a deadlock on the main thread that is holding the AX queue takes
    /// the whole app with it. The nested call runs inline instead, which is always safe because the
    /// queue is serial by construction.
    func sync<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: key) != nil {
            return work()
        }
        return queue.sync(execute: work)
    }

    /// Runs `work` on the AX queue without waiting. Used by the drag pipeline, whose event tap must
    /// return immediately.
    func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    /// Whether the caller is currently on the AX queue.
    var isOnQueue: Bool { DispatchQueue.getSpecific(key: key) != nil }
}
