# Light Stats

> `CLAUDE.md` and `AGENTS.md` are mirrors — any edit to one must apply to the other.

macOS menu bar system monitor. CPU, GPU, memory, disk, disk I/O, network, proxy, battery,
temperature, fan, processes, AI subscription usage, cleaning mode, self-update, and a
composite health score. Compact status item + detailed popover panel.

macOS 14+ · Swift 5.9+ · SwiftUI + AppKit · zero third-party dependencies · `LSUIElement = YES`

## Layout

```
Light Stats/
├── LightStatsApp.swift              # @main, Settings scene
├── AppDelegate.swift                # NSStatusItem + popover lifecycle
├── Models/                          # Pure data structs; no logic, no imports
│   ├── CPUInfo.swift
│   ├── GPUInfo.swift
│   ├── MemoryInfo.swift
│   ├── DiskInfo.swift
│   ├── NetworkInfo.swift
│   ├── ProxyInfo.swift
│   ├── BatteryInfo.swift
│   ├── ProcessStats.swift
│   ├── AIUsageInfo.swift
│   ├── HealthScore.swift            # Dimension sub-scores + final 0–100
│   ├── CoreType.swift
│   ├── AppGroup.swift
│   ├── MetricTrends.swift           # Per-metric rising/falling/steady trend
│   └── ReleaseInfo.swift            # SemanticVersion + GitHub Release JSON
├── Services/                        # System data collection; no View/ViewModel imports
│   ├── PowerService.swift           # IOKit battery + SMC sensors
│   ├── ProcessService.swift         # proc_listallpids + task_info
│   ├── ExitNodeService.swift        # Geo-IP exit-node (actor)
│   ├── DiskIOService.swift          # IOKit disk IO counters
│   ├── HealthScoreService.swift     # Pure static compute(): 0–100 pressure score
│   ├── ProxyDetector.swift          # System proxy + env + tunnel detection
│   ├── ClaudeUsageService.swift     # Claude Code API usage
│   ├── CodexUsageService.swift      # Codex CLI usage
│   ├── GeminiUsageService.swift     # Gemini CLI usage (OAuth refresh flow)
│   ├── UpdateService.swift          # GitHub Release → download → verify → install (actor)
│   ├── KeyboardLockService.swift    # CGEventTap key suppression (cleaning mode)
│   ├── ScrollDirectionService.swift # CGEventTap scroll-direction reversal (opt-in)
│   ├── WindowSnappingService.swift  # AX window move/resize snap engine
│   ├── WindowSnapPreviewService.swift # Snap-zone preview overlay
│   ├── MagnetHotKeyService.swift    # Global snap hotkeys (CGEventTap, opt-in)
│   ├── TitlebarGestureService.swift # Titlebar swipe-to-snap (CGEventTap, opt-in)
│   ├── AccessibilityPermission.swift # Shared AXIsProcessTrusted check + prompt
│   ├── LaunchAtLoginService.swift   # SMAppService login-item registration
│   ├── PageRateService.swift        # vm_statistics64 swap page rate (nonisolated)
│   ├── SMCInfo.swift                # SMC temperature + fan
│   ├── CLIBinaryResolver.swift      # which/path for AI CLIs
│   └── AIUsage/                     # Shared AI-usage fetch helpers
│       ├── PTYProbe.swift           # Reusable PTY capture engine (Claude/Codex CLI scrape)
│       └── KeychainCredentialReader.swift # `security` CLI Keychain read (no auth dialog)
├── ViewModels/                      # @Observable / ObservableObject; @MainActor for UI
│   ├── SystemMonitor.swift          # Timer → collect → publish SystemSnapshot
│   ├── SettingsManager.swift        # UserDefaults-backed preferences
│   ├── AIUsageMonitor.swift         # Claude/Codex/Gemini polling coordinator
│   ├── AppMemoryManager.swift       # Process list + cleanup state
│   ├── LocalizationManager.swift    # Language change broadcast
│   ├── SystemAppFilter.swift        # Apple-signed app exclusion list
│   ├── CleaningModeViewModel.swift  # 60s countdown + keyboard lock
│   └── UpdateManager.swift          # Update UI state machine
├── Views/                           # SwiftUI panels/settings; AppKit for menu bar
│   ├── StatusBar/StatusBarView.swift
│   ├── Popover/
│   │   ├── PopoverContentView.swift       # Tab root
│   │   ├── OverviewTabView.swift
│   │   ├── CleanupTabView.swift
│   │   ├── DebugSnapshot.swift
│   │   └── Components/
│   │       ├── BentoCard.swift
│   │       ├── AppRowView.swift
│   │       ├── ChildProcessRowView.swift
│   │       ├── AIUsageCard.swift
│   │       ├── QuickStatCard.swift
│   │       ├── Sparkline.swift             # SwiftUI trend mini-chart
│   │       ├── SpinningFanIcon.swift       # CADisplayLink fan animation
│   │       ├── TabButton.swift
│   │       ├── VisualEffectView.swift      # NSViewRepresentable blur
│   │       └── ColorExtensions.swift
│   ├── Settings/SettingsView.swift
│   ├── About/AboutView.swift
│   ├── CleaningMode/
│   │   ├── CleaningModeOverlayController.swift
│   │   └── CleaningModeOverlayView.swift
│   ├── Toast/ToastCenter.swift            # Transient toast notifications
│   └── Update/UpdateWindowView.swift
├── Utilities/
│   ├── ByteFormatter.swift          # Stateless byte/rate formatting
│   ├── MetricHistory.swift          # Ring buffer of recent samples (sparklines)
│   └── WindowSnapIconProvider.swift # SF Symbol icons for snap actions
└── Resources/
    ├── en.lproj/Localizable.strings
    ├── zh-Hans.lproj/Localizable.strings
    ├── ja.lproj/Localizable.strings
    └── ko.lproj/Localizable.strings
```

Dependency direction:

```
Views → ViewModels → Services → Models
         Utilities ↗
```

- Models import nothing from the app.
- Services import Models; forbidden from importing ViewModels or Views.
- ViewModels import Services and Models.
- Views import ViewModels and Models.
- Utilities are stateless, know nothing about the app, imported anywhere.

## Layer Contracts

### Models

```swift
// Every model is a Sendable struct. No methods beyond computed formatting.
struct CPUInfo: Sendable {
    var usage: Double            // 0–100
    var cores: Int
    var loadAverage: LoadAverage
    var perCoreUsage: [Double]
}
```

One type per file. File name matches the primary type. No `@Published`, no Combine.
A Model is a snapshot, not a state machine. It never imports Services, ViewModels, or Views.

### Services

Two shapes, chosen by concurrency need:

```swift
// Shape A: nonisolated — pure computation or fast synchronous syscall.
// Caller runs it on its own actor/queue.
nonisolated final class PageRateService: @unchecked Sendable {
    func sample() -> Double { /* vm_statistics64 */ }
}
// Also valid: an enum with static functions (HealthScoreService).

// Shape B: actor — mutable cached state or network calls.
// Serialises access without manual locks.
actor ExitNodeService {
    private var cache: ProxyInfo?
    func detect() async -> ProxyInfo { /* HTTP geo-IP, cache-miss → fetch */ }
}

// Shape C: @MainActor lifecycle service — owns a CGEventTap / AX session with
// explicit start()/stop(). Used by every opt-in "extra tool" so AppDelegate can
// install the tap only when its switch is on and tear it down the moment it is off.
@MainActor final class ScrollDirectionService: ScrollReversing {
    private(set) var isRunning: Bool
    func start() -> Bool   // returns false if Accessibility permission is missing
    func stop()
}
```

Services return Model types. They never return View types or ObservableObject conformances.
They are forbidden from importing ViewModels or Views.

**Shape C — opt-in event-tap services.** `ScrollDirectionService`, `MagnetHotKeyService`,
`TitlebarGestureService`, and `KeyboardLockService` each own a `CGEventTap` (or an
Accessibility session via `WindowSnappingService`) behind a `start()/stop()` lifecycle.
They are the only services that hold OS-level taps, so they are also the only ones gated by
the "default off" rule: AppDelegate creates the tap **only** when the owning switch turns on
(`windowManagementEnabled` for the window trio; `scrollReverse*` for scrolling; cleaning-mode
activation for the keyboard lock) and calls `stop()` immediately when it turns off. `start()`
returns `false` when Accessibility permission is missing — the caller keeps the switch on and
retries on `didBecomeActive`. None of these run on a clean default install. See
*Default form (zero-intrusion)* below.

### ViewModels

```swift
// Shape A: @Observable (Swift 6) — published snapshots consumed by SwiftUI views.
@Observable
final class SystemMonitor {
    var snapshot: SystemSnapshot
    func startMonitoring(interval: TimeInterval) { /* Timer → collect → publish */ }
}

// Shape B: ObservableObject — shared singletons where @Published + didSet
// drives UserDefaults persistence or property-observer side effects.
final class SettingsManager: ObservableObject {
    @Published var refreshRate: RefreshRate { didSet { save(refreshRate, for: .refreshRate) } }
    static let shared = SettingsManager()
}
```

- `SystemMonitor` owns the sampling loop. It calls Services, assembles a `SystemSnapshot`.
- `SettingsManager` is the single source of truth for all user preferences.
- `@MainActor` on any ViewModel that manages UI windows (`CleaningModeViewModel`, `UpdateManager`).
- `AppMemoryManager` is `ObservableObject` (predates `@Observable`; uses `@Published` observers for process-list mutations).

### Views

```swift
struct OverviewTabView: View {
    @Environment(SystemMonitor.self) var monitor  // injected, never created locally
    var body: some View { /* read monitor.snapshot */ }
}
```

Views receive ViewModels via `@Environment` or `@ObservedObject`. They never instantiate
Services directly — `Views → ViewModels → Services`.

SwiftUI for panels and settings. AppKit (`NSViewRepresentable`, `NSHostingView`) for the
menu bar status item. `CleaningModeOverlayController` is the only View-layer class that
owns `NSWindow` instances (a bridge, not a ViewModel).

## Concurrency

| Concern | Mechanism | Why |
|---------|-----------|-----|
| UI-bound state | `@MainActor` | SwiftUI observes on main; AppKit renders on main |
| Published snapshots | `@Observable` (Swift 6) | Compiler-enforced observation, no `objectWillChange` |
| UserDefaults prefs | `ObservableObject` + `@Published` | `didSet` writes to UserDefaults; Combine-compatible |
| Cached network results | `actor` | Serialises mutable cache access; no locks |
| Sync syscalls | `nonisolated` class or `enum` | Caller runs on own actor; no isolation needed |
| Fire-and-forget | `Task { }` | Scoped to owning actor context |
| Detached work | `Task.detached { }` | Must not inherit caller's actor isolation |

No blocking waits inside async contexts. No `DispatchQueue` for new code — use Swift Concurrency.

## Configuration

`SettingsManager` is the single `UserDefaults` facade. Adding a preference:

```
1. Add a Key case
2. Add a @Published property with didSet { save(value, for: .key) }
3. Initialise from UserDefaults in init()
4. Add the UI control in SettingsView
5. Add the key to all four Localizable.strings files
```

Refresh rate is `RefreshRate` enum with raw `TimeInterval`: `low = 5s`, `medium = 2s`, `high = 1s`.

Health score dimension toggles: `healthInclude{CPU,Memory,Load,Temperature,GPU,Power}`,
all default `true`, assembled into `HealthScoreService.DimensionToggles` and passed
through `SystemMonitor.collect(...)` → `compute(...)`. `Power` is hardware-chosen: battery
on laptops, disk I/O on desktops. All-off → `HealthScore.perfect` (100).

## Health Score

`HealthScoreService.compute(...)` is a pure static function. Inputs: raw sensor readings +
optional `DimensionToggles`. Output: `HealthScore` with per-dimension sub-scores and a
smoothed 0–100 total.

### What it measures

Pressure, not capacity. "Is this Mac sluggish right now?" A machine with high RAM
utilisation but normal memory pressure stays near 100. A machine at 50% CPU with swap
thrashing drops hard.

Disk usage % was deliberately removed — it is a slow-moving capacity alert, not a
responsiveness signal. Memory uses pressure level + swap ratio, not usage %, because
Apple Silicon compresses inactive pages: "30 GB used on a 32 GB Mac" is often fine
when pressure stays normal and swap is near zero.

### Dimensions

| Dimension | Weight | Signal | Score curve |
|-----------|-------:|--------|-------------|
| `cpu` | 25 | usage % | ≤50→100, 50–85→linear 100→60, 85+→linear 60→0 |
| `memory` | 30 | min(pressure score, swap%RAM score) | pressure: normal=100, warning=55, critical=15. swap%RAM: ≤2%→100, 2–10%→linear 100→60, 10–25%→linear 60→0 |
| `load` | 15 | LoadAvg(1m) ÷ core count | ≤0.7→100, 0.7–1.0→linear 100→60, 1.0–2.0→linear 60→0 |
| `temperature` | 20 | min(SMC temp score, thermal state score) | temp ≤60→100, 60–85→linear 100→60, 85+→linear 60→0. thermal: nominal=100, fair=80, serious=45, critical=10 |
| `gpu` | 15 | utilisation % | ≤70→100, 70–90→linear 100→60, 90+→linear 60→0 |
| `power` | 10 | battery charge (laptop) or disk I/O MB/s (desktop) | on AC=100. discharge≥40%→100, <20%→0. diskIO: ≤50→100, 150→60, 300→0 |

Weights are relative: absent dimensions (sensor missing, or toggled off) drop out and
the remainder renormalises. All-off → 100.

### Algorithm

1. Per-dimension sub-score via piecewise-linear interpolation.
2. Weighted average: `raw = Σ(score_d × weight_d) / Σ(weight_d)`.
3. Bottleneck cap: a single saturated performance dimension causes visible lag even if
   others are fine. Performance set = `{cpu, memory, load, temperature, gpu}`. `power`
   is excluded — battery/diskIO is not a lag source. `total = min(raw, worstPerformanceScore + 25)`.
4. EMA smoothing: `α = 0.35` (new sample 35%). Prevents jitter.
5. `PageRateService.sample()` provides real-time swap page rate (MB/s) as a companion
   signal to the swap-occupancy ratio in the memory dimension.

Thermal throttling enters via `ProcessInfo.thermalState`, folded into the temperature
dimension. `thermalState` is always readable (unlike SMC, which requires an IOKit bridge),
so the temperature dimension is always present.

### Grades

90–100 excellent · 75–89 good · 60–74 fair · 40–59 poor · <40 critical

## Cleaning Mode

Locks the keyboard for 60 seconds so the user can wipe the keyboard without spurious input.

```
CleaningModeViewModel (@MainActor, ObservableObject)
 ├── KeyboardLockService: CGEventTap swallows all key-down events
 ├── Timer: 60s → auto-exit (decoupled from tap health)
 └── CleaningModeOverlayController: per-screen full-screen translucent NSWindow
      └── CleaningModeOverlayView: icon + countdown + "End" button (mouse-only exit)
```

Entry: `CleaningModeViewModel.shared.activate()`. Requires Accessibility permission
(`kAXTrustedCheckOptionPrompt`). Starts tap + timer + overlays simultaneously.

Safety: the countdown timer is decoupled from the `CGEventTap`. If the tap fails
silently, the timer still fires and exits. The user can never get stuck. The "End"
button is the only manual exit — keyboard is fully suppressed.

## Auto-Update

Zero-dependency self-updater. Checks GitHub Releases, downloads the DMG, verifies it
cryptographically, replaces the running app via a detached shell script after exit.

```
UpdateManager (@MainActor, ObservableObject)
 ├── phase: idle → checking → downloading(pct) → installing → idle
 └── UpdateService (actor)
      ├── check(): GET /repos/EvilIrving/light-stats/releases/latest
      ├── download(): stream DMG to temp file; report progress via callback
      ├── verify(): three-stage gate — all must pass
      │   ├── codesign --verify --deep          (signature valid)
      │   ├── spctl --assess --verbose           (notarised)
      │   └── codesign -dv → TeamIdentifier      (matches QZZ878S3NS)
      └── install(): mount DMG → copy .app to staging → write replace.sh → exit(0)
```

Any verification failure → reject update, surface error, offer manual download link.
The replace script runs detached, waits for the old PID to exit, atomically swaps the
app bundle, and relaunches. `UpdateManager` checks once at startup; can be triggered
from the About view.

## Style

### Hard rules

- **No `print()` / `NSLog()`.** Use `os.Logger`. Includes `#Preview` blocks. SwiftLint:
  `no_print` = warning, `no_nslog` = error.
- **No force-unwrap (`!`)** unless trivially provable with a comment.
- **`guard let` over `if let`** for early exits.
- **`var x: Type?`** not `var x: Type? = nil`.
- **`for x in xs where cond {}`** not `for x in xs { if cond {} }`.
- **`x += 1`** not `x = x + 1`.
- **No `let _ = someOptional`** — use `!= nil`.
- **One type per file.** Tightly coupled private helpers excepted.
- **File structure:** imports → type declaration → properties → init → methods → extensions.

### Lint thresholds

CI runs `swiftlint lint --strict`. Every warning is a hard error. The numbers below are the
real `warning` thresholds in `.swiftlint.yml` (each has a higher hard `error` ceiling). They
are deliberately loose — several files already exceed the stricter limits an earlier draft
documented, so tightening them is deferred (it would require splitting oversized files first).

| Rule | warning | error |
|------|--------:|------:|
| `line_length` | 140 (comments, URLs exempt) | 200 |
| `function_body_length` | 90 lines | 120 |
| `file_length` | 800 lines | 1000 |
| `type_body_length` | 500 lines | 600 |
| `cyclomatic_complexity` | 16 | 20 |
| `function_parameter_count` | 10 | 15 |
| `large_tuple` | 4 members | 6 |
| `nesting` (type level) | 3 levels | — |
| `identifier_name` | ≥2 chars (`id`/`x`/`y`/`i` + a few syscall/JSON field names excluded) | — |
| `type_name` | ≥3 chars | — |

`force_cast` / `force_try` are `warning`. Opt-in rules include `unowned_variable_capture`
(prefer `weak` over `unowned` in captures) — note the rule name; `unowned_guard` is **not** a
real SwiftLint rule and must never be re-added.

Local command: `swiftlint lint --strict && swiftlint --fix --strict && swiftlint lint --strict`.
`--fix` handles trailing whitespace, redundant optional init, etc.; line-length and complexity
must be fixed by hand.

### AppKit focus rings

SwiftUI's `.focusEffectDisabled()` does not suppress AppKit-native focus rings on
`NSSwitch`, `NSSegmentedControl`, `NSButton`. Apply `.focusable(false)` to the root
container of each window/popover — it propagates to all descendants.

```swift
ScrollView { ... }.focusable(false)   // Settings root
VStack { ... }.focusable(false)        // Popover root
```

## Localization

Four languages: en, zh-Hans, ja, ko.

User-facing strings: `String(localized:)` or `NSLocalizedString`. Adding a key means
updating all four `Resources/<lang>.lproj/Localizable.strings`. Coverage check:
`./validate_localization.sh`. `LocalizationManager` broadcasts language changes so
views reload.

## Build

```bash
# Debug — one-shot: pkill running instance → build → open.
# Run it when a change needs to be seen running: UI tweaks, anything needing visual
# verification, or after finishing a complete feature. Skip it for pure logic,
# refactors, copy/localization, or doc edits — those don't need a launch.
./debug-run.sh

# Debug — manual equivalent. Always pass -derivedDataPath; without it, opening
# build/DerivedData/… launches a stale previous build from ~/Library/Developer/Xcode/DerivedData.
xcodebuild -project "Light Stats.xcodeproj" -scheme "Light Stats" \
  -configuration Debug -derivedDataPath build/DerivedData build
open "build/DerivedData/Build/Products/Debug/Light Stats.app"

# Release DMG
./build.sh
```

Force-quit before relaunching: `pkill -9 -f "Light Stats"` (`debug-run.sh` does this for you when you do need to launch).

### CI

| Workflow | Trigger | Action |
|----------|---------|--------|
| `build.yml` | Every push/PR | Lint + test + build |
| `deploy.yml` | Main branch | Build + upload DMG artifact |
| `release.yml` | `v*` tags | Sign + notarise + GitHub Release |

### Tests

```bash
xcodebuild test -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" -destination 'platform=macOS'
```

The `LightStatsTests` unit-test target is wired into the project on the shared `Light Stats`
scheme (regenerate with `ruby script/add_test_target.rb` if the pbxproj is rebuilt). Tests host
in the app target via `TEST_HOST`; `LightStatsTests/` is a synchronized folder group, so new
`.swift` / fixture files are picked up automatically. Suites:

- `HealthScoreServiceTests` — every scoring-curve knee, weight renormalisation, the bottleneck
  cap (and that `power` is excluded from it), EMA smoothing, grade boundaries.
- `SettingsDefaultsTests` — the "default off" contract on a clean `UserDefaults` suite, via
  `SettingsManager(defaults:)`. (Instances are retained for the process: a fresh
  `@MainActor`-isolated `SettingsManager` deinit trips a Swift Concurrency back-deploy
  double-free on macOS 14.x; the production singleton never deallocates, so this is test-only.)
- `AIUsageParsingTests` — Claude/Codex/Gemini response parsers against sanitized JSON fixtures
  in `LightStatsTests/Fixtures/` (valid / partial / malformed). This is the P4 regression net;
  the parse seams (`ClaudeUsageService.parseUsageJSON`, `CodexUsageService.parseUsageJSON`,
  `GeminiUsageService.parseQuotaResponse`) are `internal` so `@testable` can reach them.
- `PTYProbeTests` — drives the shared `PTYProbe` capture engine with a synthetic shell
  script (no claude/codex CLI needed): completion predicate, timeout, buffer reset, ANSI
  stripping. The live CLI TUI paths can't run under the test host, so this is their net.
- `LightStatsSmokeTests` — model sentinels + formatter sanity.

## Default form (zero-intrusion)

The product is "monitoring core + extra tools that are off by default". Every capability
beyond read-only monitoring (window management, scroll reversal, AI usage, exit-node
detection) ships **off**. A user who never opts in must not see an entry point, be asked
for a permission, or pay any tap / collection / network cost.

Cold-start checklist — must hold on a clean install (empty `UserDefaults`):

- **No menu bar icon beyond monitoring.** The window-controls icon (`rectangle.split.2x1`)
  is created lazily and only when `windowManagementEnabled` is on. Default install shows
  only the monitoring status item.
- **No Accessibility prompt.** `AXIsProcessTrustedWithOptions` is never called by default;
  permission is requested only when the user actively enables a feature that needs it
  (scroll reversal, window management, cleaning mode).
- **No `CGEventTap`.** scroll / keyboard / window taps are all off by default; nothing is
  installed until the matching switch is turned on.
- **No outbound request** except `autoCheckUpdates` (on by default, user-disablable).
  Exit-node detection and AI usage polling are opt-in.
- **Window management is a single master switch.** `windowManagementEnabled` (default off)
  drives the menu bar icon **and** snap shortcuts **and** titlebar gestures together —
  on = icon + shortcuts + gestures + taps all start; off = all stop. There are no
  sub-switches.
- **Runtime off-path is as thorough as terminate.** Turning a feature off in Settings must
  `stop()` its services / taps / observers immediately, not only at
  `applicationWillTerminate`.

## What this app is not

- Not an Activity Monitor replacement — status indicator, not full diagnostic. Top-N processes only.
- No per-process network breakdown — aggregate per-interface only.
- No custom chart rendering — SwiftUI shapes + AppKit views; no Core Graphics / Metal.
- No plugin system — every metric is a built-in Service.
- No background daemon — runs as a normal menu bar app; no XPC, no LaunchAgents.
- No remote telemetry — the app phones home only for user-initiated update checks and opt-in exit-node detection.
- No Intel-only or pre-macOS-14 support — Apple Silicon is the primary target.
