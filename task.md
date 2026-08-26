# Display Brightness Control — Implementation Tracker

Last updated: 2026-08-23

## Current-state audit

- [x] Confirmed the current `main` worktree is clean and contains no display-control implementation.
- [x] Checked branches, stashes, worktrees, reflog, and unreachable Git commits/trees; no recoverable prior `DisplayControl` / `DDC` / brightness files were found.
- [x] Confirmed `SystemMonitor` has no DDC code and should remain unchanged.

## Work plan

- [x] Inspect current app lifecycle, popover composition, settings patterns, project build settings, and unit-test conventions.
- [x] Implement display-control models and pure DDC packet/conversion primitives with unit tests.
- [x] Implement native brightness wrapper, ARM64 IORegistry matcher, private I²C transport, environment gate, controller cache, and top-level service.
- [x] Implement `DisplayControlManager` lifecycle, per-display state, slider grip protection, polling, persistence fallback, and debounced latest-value writes.
- [x] Wire the opt-in setting (default off), app/popover lifecycle injection, and conditional Overview brightness section.
- [x] Add concise localized strings in en, zh-Hans, ja, and ko.
- [x] Configure the main target for the private display APIs without affecting Intel builds.
- [x] Add regression tests for packet/checksum, raw-percent conversion, capability state, gate behavior, debounce behavior, and matcher scoring.
- [x] Run formatting/lint, localization validation, unit tests, and a debug build/launch; fix all failures.
- [x] Review the final diff for architecture, zero-intrusion defaults, lifecycle shutdown, and documentation consistency.

## Display identity refinement

- [x] Rename the model field to `displayName` and derive a stable vendor/model/serial `storageID`.
- [x] Resolve names through `NSScreen.localizedName`, then CoreDisplay, then localized fallback.
- [x] Sort built-in first, then external displays by screen position, name, and stable identity.
- [x] Render a persistent built-in/external label on every display row and update all four localizations.
- [ ] Add focused identity regression tests and rerun lint, localization, XCTest, builds, and live visual verification. *(in progress)*
- [x] Follow-up: move the Displays section below AI Usage; hide the whole section when no displays are detected (removed probing/empty states and their localization keys).
- [x] Follow-up: serialize refreshes while one is in flight; this removes overlapping DDC probes that produced timed-out kernel-call skips on the external display.
- [x] Follow-up: fix section dividers so AI Usage, Displays, and Network each have exactly one hairline between them in all visibility combinations (Displays now owns a trailing divider instead of a leading one).
- [x] Follow-up: inject `DisplayControlManager` into `VisualThemeCaptureTests` and pin display control off there; fixes the test-host crash from the new environment object and keeps captures deterministic.

## Progress notes

- The requested implementation is substantial and spans the model/service/view-model/view layers. Work will be performed directly in this worktree without subagents.
- Private API use will be isolated behind narrow declarations and `#if arch(arm64)` implementations. The first release will include hardware brightness only: no OSD and no gamma dimming.
- Resumed implementation from the tracker. The worktree contains no prior display-control source changes; `task.md` is the only untracked file, and existing repository history/state will be preserved.
- Audit result: the main app and test targets use synchronized folder groups, so new Swift/test files are discovered automatically. The app target needs only bridging-header and private-framework build settings.
- Lifecycle insertion points are `AppDelegate.setupPanel()`, `togglePanel()`, `dismissPanel(reason:)`, the opt-in settings publisher, `didBecomeActive`, and `stopRuntimeServices()`. `SystemMonitor` remains untouched.
- DDC protocol facts used here: five-argument IOAVService I2C calls, checksum address `0x37`, MCDP29XX route address `0xB7`, standard brightness VCP `0x10`, and legacy fallback `0x13`.
- Implementation is independently structured and limited to brightness hardware control.
- Added independent model and pure service primitives, plus `DisplayControlCoreTests`. The focused XCTest run executed 8 tests with 0 failures.
- Added private API bridge/build settings, native brightness access, ARM64 registry matching, MCDP29XX routing, serialized I2C transport with a per-call watchdog, capability probing/cache, environment gate, top-level service, manager lifecycle, Settings opt-in, Popover UI, and four-language copy.
- The fully wired focused run executed 14 tests with 0 failures: 8 core protocol/cache/scoring tests, 5 gate/debounce tests, and the clean-install default-off test.
- Real-hardware read-only validation found the built-in display at 53% and a DELL U2725QE at 81%; one external DDC service matched successfully. No brightness write was performed during validation.
- Replaced the initial full-tree IORegistry scan after it measured 3m38s on real hardware. Targeted framebuffer/proxy enumeration plus DCP index pairing now completes matching and discovery in under 0.1s on the same setup.
- Visual inspection of the 360x780 live Popover confirmed both display rows and sliders render without overlap, clipping, nested cards, or section plates.
- Final verification: 135 XCTest tests passed; ARM64 signed Debug build/launch passed; x86_64 Debug cross-build passed; SwiftLint strict reported 0 violations; all 274 localization keys are present in all four languages; `git diff --check` passed.
- Temporary validation preferences were removed from both the global and container defaults domains. The final launched app is back on the original default-off display-control state.
- Final review confirmed the off-path registers no display observers and performs no display enumeration/DDC I/O; runtime disable and termination stop polling/writes and clear service routes. No gamma dimming, OSD, volume, contrast, or unrelated refactor was added.
- Refinement requested after the initial implementation: make display identity/name provenance explicit and show the built-in/external role on each row. This follow-up is being implemented directly without changing the DDC transport contract.
- Renamed the model field to `displayName`; display names now resolve through the matching `NSScreen.localizedName`, then CoreDisplay product names, then localized built-in/external fallbacks.
- Storage keys now use only vendor/model/serial in a deterministic hex format. Rows sort built-in first, then by NSScreen position, localized name, and storage ID.
- Each row now shows a fixed built-in/external role label, retaining an explicit unsupported suffix when needed. Four-language coverage is 276 keys.
- Focused refinement verification executed 15 display-control tests with 0 failures; focused SwiftLint and localization validation passed.
- Per user correction, built-in displays now show the Mac's own product name (`system_profiler SPHardwareDataType -json` machine_name, cached) instead of the panel name such as "Built-in Retina Display"; the role label stays on the right. `displayName` is now optional and the UI omits the name text when it is unavailable.
- Per user correction, the Displays section now renders below AI Usage and disappears entirely when no displays are detected.
- Final refinement verification: 137 XCTest tests passed (including VisualThemeCaptureTests); SwiftLint strict 0 violations; 274 localization keys across four languages; ARM64 Debug build/launch and x86_64 cross-build both succeeded.
- Live panel readout confirms: AI 用量 → 显示器 (MacBook Pro · 内建屏 68%, DELL U2725QE · 外接屏 77%) → 网络, with discovery completing in about one second and no DDC watchdog skips after refresh serialization.
