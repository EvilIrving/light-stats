import Darwin

/// Revalidate immediately before every signal, including escalation after an await.
/// macOS has no pidfd-style atomic compare-and-signal API; this narrows, but cannot
/// eliminate, the race between the final identity read and kill().
nonisolated enum ProcessSignalGuard {
    static func send(
        _ signal: Int32,
        to identity: ProcessIdentity,
        readIdentity: (Int32) -> ProcessIdentity? = ProcessIdentityReader.read,
        deliver: (Int32, Int32) -> Int32 = { Darwin.kill($0, $1) }
    ) -> Bool {
        guard identity.pid > 0, readIdentity(identity.pid) == identity else { return false }
        return deliver(identity.pid, signal) == 0
    }
}
