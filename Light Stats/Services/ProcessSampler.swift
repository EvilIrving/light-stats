import Foundation
import Darwin

/// Serial native footprint sampling. No polling when the cleanup panel is hidden;
/// closely spaced requests reuse the same identity-checked snapshot.
actor ProcessSampler {
    static let shared = ProcessSampler()
    private var latest: [TopProcessInfo] = []
    private var sampledAt: TimeInterval?

    func sample() -> [TopProcessInfo] {
        let now = ProcessInfo.processInfo.systemUptime
        if let sampledAt, now - sampledAt < 0.5 { return latest }
        guard let pids = Self.processIDs() else {
            DiagnosticLogService.record(category: "processMemory", action: "enumerationFailed", fields: [
                "reasonCode": "processListUnavailable", "source": "proc_listallpids"
            ])
            return latest
        }
        var bundles: [String: ProcessBundleInfo] = [:]
        let rows = pids.compactMap { Self.read($0, bundles: &bundles) }
        latest = rows
        sampledAt = now
        DiagnosticLogService.recordSample(category: "processMemory", action: "nativeSample", fields: [
            "enumeratedCount": .privateValue(.integer(Int64(pids.count))),
            "sampledCount": .privateValue(.integer(Int64(rows.count))),
            "unavailableFootprintCount": .privateValue(.integer(Int64(rows.filter { $0.memoryBytes == nil }.count))),
            "durationMilliseconds": .privateValue(.double((ProcessInfo.processInfo.systemUptime - now) * 1_000))
        ])
        return rows
    }

    private static func processIDs() -> [pid_t]? {
        // proc_listallpids returns a PID count, while its buffer size is in bytes.
        var capacity = max(Int(proc_listallpids(nil, 0)) + 128, 256)
        for _ in 0..<4 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let count = pids.withUnsafeMutableBytes { buffer in
                proc_listallpids(buffer.baseAddress, Int32(buffer.count))
            }
            guard count > 0 else { return nil }
            if count < capacity { return Array(Set(pids.prefix(Int(count)).filter { $0 > 0 })).sorted() }
            capacity *= 2
        }
        return nil
    }

    private static func read(_ pid: pid_t, bundles: inout [String: ProcessBundleInfo]) -> TopProcessInfo? {
        guard let bsd = ProcessIdentityReader.bsdInfo(for: pid) else { return nil }
        let identity = ProcessIdentityReader.identity(pid: pid, info: bsd)
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer($0).assumingMemoryBound(to: rusage_info_t?.self))
        }
        let failure = result == 0 ? nil : errno
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let path = pathLength > 0 ? String(cString: pathBuffer) : nil
        let responsible = responsibility_get_pid_responsible_for_pid(pid)
        guard ProcessIdentityReader.read(pid) == identity else { return nil }
        if let failure {
            DiagnosticLogService.recordProbe(
                component: "processMemory", operation: "footprint", identity: "footprint.\(failure)",
                status: .unavailable, reasonCode: failure == EPERM ? "permissionDenied" : "rusageFailed",
                source: "proc_pid_rusage", fields: ["errno": .publicValue(String(failure))]
            )
        }
        let bundle: ProcessBundleInfo
        if let path {
            if let cached = bundles[path] {
                bundle = cached
            } else {
                bundle = ProcessBundleResolver.resolve(path)
                bundles[path] = bundle
            }
        } else {
            bundle = ProcessBundleInfo(execPath: nil, bundlePath: nil, bundleId: nil)
        }
        var info = bsd
        let name = withUnsafePointer(to: &info.pbi_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN * 2)) { String(cString: $0) }
        }
        return TopProcessInfo(
            pid: pid, parentPid: pid_t(bsd.pbi_ppid), command: path ?? name,
            memoryBytes: result == 0 ? usage.ri_phys_footprint : nil,
            identity: identity, bundleInfo: bundle, responsiblePid: responsible
        )
    }
}
