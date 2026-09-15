# Process and memory collection

Verified against the local macOS SDK and the installed system tools on 2026-09-15.

## Application memory

`ProcessSampler` enumerates with `proc_listallpids`, captures BSD identity and parentage,
reads `proc_pid_rusage(RUSAGE_INFO_V4)`, resolves the executable path and responsible PID,
then checks identity again. A process replaced during collection is discarded. Repeated
requests within 0.5 seconds share a snapshot. Collection is demand driven by the cleanup panel.

Every reported memory value is `ri_phys_footprint`, including small helpers. There is no
RSS threshold and no RSS fallback. A valid zero stays zero; failure stays unavailable.
An application with missing readings displays the known subtotal with `≥`, or `—` if
nothing is known. Native enumeration and footprint failures enter the diagnostic journal.

Bundle resolution keeps the outer `.app`: Chrome renderers, embedded WeChatAppEx and
extensions remain part of their host application. An independently running GUI application
keeps its own group even when another application launched it. Other workers follow
responsibility, bundle identity/path, then a bounded parent chain. Parent-chain-only
attribution grants display membership but not termination rights.

The view model uses sampled metadata rather than repeating per-process path and
responsibility syscalls on the main actor. Cancelling a refresh prevents its result from
publishing or clearing the task that replaced it.

## Process termination

A termination target is `(PID, BSD start seconds, BSD start microseconds)`, captured with
the displayed snapshot. Main-process termination, child cleanup and delayed escalation
all revalidate identity. Missing identity and PID reuse fail closed. Signals use `kill`
directly after validation, eliminating the extra `/bin/kill` spawn window.

This is not an atomic guarantee: macOS has no pidfd-style compare-and-signal API. A small
race remains between the final identity check and signal delivery. Tests inject the
identity reader and signal sender; they do not terminate live applications.

## CPU ranking and privilege boundaries

CPU ranking retains the system `/bin/ps` path. On the inspected installation `/bin/ps`
is root-owned and setuid (`-rwsr-xr-x`). Direct libproc accounting calls from an ordinary
user were denied for roughly 280 system/other-user processes. Replacing that channel
with an unprivileged sampler would silently remove system processes from the ranking.
The CPU service was moved out of Models; it is not mixed with a differently measured
native CPU percentage. Its existing `ps` CPU semantics are unchanged.

`sysctl(KERN_PROC_PID)` is a fallback for identity/parentage, not an alternative source
of physical footprint. No privileged helper, permission request or account change was added.

## System memory

`MemoryUsagePolicy` computes:

```
app memory = max(anonymous pages - purgeable pages, 0)
used = clamp(app memory + wired pages + physical compressor storage, 0...physical RAM)
```

The same policy feeds the overview/status value and cleanup details. `active_count` is
not a measure of application ownership: anonymous pages can be inactive, and active
pages can be file-backed. Physical compressor storage is `compressor_page_count`, not
the uncompressed size of the compressed contents. File-backed caches are excluded from
application memory. This total is not the sum of per-process footprints or a claim of
byte-for-byte agreement with Activity Monitor's private implementation.

The SDK explicitly says speculative pages are already included in `free_count`.
The previously suggested `total - free - speculative` would subtract them twice and
was not implemented. Apple's [Activity Monitor guide](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac)
describes app, wired, compressed memory and cached files separately; `top`'s physical
occupancy display must not be treated as proof of Activity Monitor's exact formula.

## Corrections to the earlier package analysis

The local `sys/proc_info.h` defines `PROC_PIDTBSDINFO = 3` and `PROC_PIDTASKINFO = 4`.
A call with flavor 3 and a 136-byte buffer is BSD process information, not evidence of
reading resident memory. An absent `footprint` string in a binary does not prove that
the field is unused. The earlier claims that Tencent's entire memory path and grouping
were proven from these observations are withdrawn. None of the fixes depend on them.

## Validation

- `ProcessSamplingTests`: identity reuse, microsecond identity changes, escalation,
  invalid PIDs, unavailable identity, signal failure, uniform totals beyond 80 processes,
  missing data, and a live read-only sample of the test host.
- `ProcessAttributionPolicyTests`: independent GUI app ownership, responsibility,
  reparented crash handlers, helper suffixes, parent-chain permissions, cycles, depth
  bounds, and embedded app/extension paths.
- `MemoryUsagePolicyTests`: ownership-based totals, purgeable exclusion and bounded math.
- Full `./script/test.sh`: 604 tests passed. Strict SwiftLint and localization checks passed.
