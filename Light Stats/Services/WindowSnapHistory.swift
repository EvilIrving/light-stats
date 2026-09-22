//
//  WindowSnapHistory.swift
//  Light Stats
//

import CoreGraphics

/// Remembers, per window, where it was before we snapped it and where we put it.
///
/// This is what makes `restore` trustworthy, and it is the piece the previous implementation was
/// missing entirely: `saveFrameIfNeeded` was only reachable from the engine's own placement path,
/// so any snap that went through the system's menu item returned early and never recorded an
/// original frame — leaving "restore" permanently disabled for those windows.
///
/// Keeping `placed` as well as `original` is what makes a restore safe: if the window is no longer
/// where we left it, the user (or another tool, or
/// the system) moved it, and restoring to a rectangle from three actions ago would be worse than
/// doing nothing.
nonisolated struct WindowSnapHistory<Key: Hashable> {

    struct Record: Hashable {
        /// Where the window was before our first snap in this run.
        var original: CGRect
        /// Where we last put it.
        var placed: CGRect
    }

    private var records: [Key: Record] = [:]

    init() {}

    /// Ensures a restore point exists, without overwriting a live one.
    ///
    /// If the window has been moved by something other than us since we placed it, the stored
    /// restore point no longer describes anything real, so the current position becomes the new
    /// one. That decision is made automatically here rather than passed in by the caller.
    mutating func prepare(key: Key, currentFrame: CGRect) {
        guard let existing = records[key] else {
            records[key] = Record(original: currentFrame, placed: currentFrame)
            return
        }
        if !WindowSnapGeometry.framesApproximatelyEqual(existing.placed, currentFrame, tolerance: 2) {
            records[key] = Record(original: currentFrame, placed: currentFrame)
        }
    }

    /// Records where the window ended up, without disturbing the original restore point.
    mutating func recordPlacement(key: Key, frame: CGRect) {
        guard var record = records[key] else {
            records[key] = Record(original: frame, placed: frame)
            return
        }
        record.placed = frame
        records[key] = record
    }

    func record(for key: Key) -> Record? { records[key] }

    /// Whether a restore to the stored original is still meaningful for the window's current frame.
    func canRestore(key: Key, currentFrame: CGRect) -> Bool {
        guard let record = records[key] else { return false }
        return WindowSnapGeometry.framesApproximatelyEqual(record.placed, currentFrame, tolerance: 3)
            && !WindowSnapGeometry.framesApproximatelyEqual(record.original, currentFrame, tolerance: 1)
    }

    /// The frame a restore should produce, consuming the record.
    mutating func takeRestoreFrame(key: Key, currentFrame: CGRect) -> CGRect? {
        guard canRestore(key: key, currentFrame: currentFrame), let record = records[key] else { return nil }
        records[key] = nil
        return record.original
    }

    mutating func forget(key: Key) {
        records[key] = nil
    }

    mutating func removeAll() {
        records.removeAll()
    }

    var count: Int { records.count }
}
