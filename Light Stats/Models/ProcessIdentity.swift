/// A PID alone can identify a different process after exit. BSD start time is stable
/// for the lifetime of a process, including exec(), and is available without task ports.
nonisolated struct ProcessIdentity: Hashable, Sendable {
    let pid: Int32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}
