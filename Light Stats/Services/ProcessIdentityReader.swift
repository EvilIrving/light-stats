import Foundation
import Darwin

nonisolated enum ProcessIdentityReader {
    static func bsdInfo(for pid: pid_t) -> proc_bsdinfo? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard result == size else { return fallbackBSDInfo(for: pid) }
        return info
    }

    /// KERN_PROC_PID exposes process identity/parentage even when libproc denies
    /// task accounting for another user. It does not provide a footprint fallback.
    static func fallbackBSDInfo(for pid: pid_t) -> proc_bsdinfo? {
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &process, &size, nil, 0) == 0,
              size == MemoryLayout<kinfo_proc>.size else { return nil }
        let start = process.kp_proc.p_un.__p_starttime
        guard start.tv_sec > 0, start.tv_usec >= 0 else { return nil }
        var info = proc_bsdinfo()
        info.pbi_pid = UInt32(pid)
        info.pbi_ppid = UInt32(max(0, process.kp_eproc.e_ppid))
        info.pbi_start_tvsec = UInt64(start.tv_sec)
        info.pbi_start_tvusec = UInt64(start.tv_usec)
        withUnsafeMutableBytes(of: &info.pbi_name) { destination in
            withUnsafeBytes(of: &process.kp_proc.p_comm) { source in
                destination.copyBytes(from: source.prefix(destination.count - 1))
            }
        }
        return info
    }

    static func identity(pid: pid_t, info: proc_bsdinfo) -> ProcessIdentity {
        ProcessIdentity(pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
    }

    static func read(_ pid: pid_t) -> ProcessIdentity? {
        guard let info = bsdInfo(for: pid) else { return nil }
        return identity(pid: pid, info: info)
    }
}
