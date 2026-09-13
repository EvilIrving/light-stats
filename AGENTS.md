# Light Stats

> `CLAUDE.md` and `AGENTS.md` are mirrors — any edit to one must apply to the other.

macOS menu bar system monitor. CPU, GPU, memory, disk, disk I/O, network, proxy, battery,
temperature, fan, processes, AI subscription usage, cleaning mode, self-update, and a
composite health score. Compact status item + detailed popover panel. Optional extras
(Finder menu, window snap, default input source, display brightness) stay off until enabled.

macOS 14+ · Swift 5.9+ · SwiftUI + AppKit · zero third-party dependencies · `LSUIElement = YES`

## Layout

```
Light Stats/
├── LightStatsApp.swift              # @main, Settings scene
├── AppDelegate.swift                # NSStatusItem + popover lifecycle
├── AppDelegate+WindowMenu.swift     # Menu-bar window-control status item
├── AppDelegate+Termination.swift    # Instant-quit + update-replace handoff
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
│   ├── AppTheme.swift               # Product preset ID (glass/film/bar/noir/dataPaper)
│   ├── FindMouseTriggerKey.swift    # User-recorded shortcut for Find My Mouse
│   ├── InputSourceOption.swift      # Selectable input source id + display name
│   ├── LicensePayload.swift         # Signed activation-code payload + Feature enum
│   ├── WindowSnapAction.swift       # Snap action shared by hotkeys, gestures, menu bar
│   ├── WindowSnapHotKey.swift       # Global shortcut: key code + modifiers → action
│   ├── SnapGestureZone.swift        # Where a swipe must start (titlebar / pointer)
│   ├── CoreType.swift
│   ├── AppGroup.swift
│   ├── MetricTrends.swift           # Per-metric rising/falling/steady trend
│   └── ReleaseInfo.swift            # SemanticVersion + GitHub Release JSON
├── Services/                        # System data collection; no View/ViewModel imports
│   ├── PowerService.swift           # IOKit battery + SMC sensors
│   ├── DiagnosticLogService.swift   # Always-on structured fault journal (schema v3)
│   ├── DiagnosticReportService.swift # User-exported support ZIP + fresh hardware probes
│   ├── PerformanceLogService.swift  # Separate opt-in product resource recording
│   ├── ProcessService.swift         # proc_listallpids + task_info
│   ├── ExitNodeService.swift        # Geo-IP exit-node (actor)
│   ├── DiskIOService.swift          # IOKit disk IO counters
│   ├── HealthScoreService.swift     # Pure static compute(): 0–100 pressure score
│   ├── ProxyDetector.swift          # System proxy + env + tunnel detection
│   ├── ClaudeUsageService.swift     # Claude Code API usage
│   ├── CodexUsageService.swift      # Codex CLI usage
│   ├── GeminiUsageService.swift     # Gemini CLI usage (OAuth refresh flow)
│   ├── UpdateService.swift          # R2 channel marker → download → verify → install (GitHub fallback)
│   ├── LicenseCodec.swift           # Base32 + activation-code wire format (mirrored by script/license-tool)
│   ├── LicenseValidator.swift       # Offline Ed25519 signature validation (embedded public key)
│   ├── KeyboardLockService.swift    # CGEventTap key suppression (cleaning mode)
│   ├── ScrollDirectionService.swift # CGEventTap scroll-direction reversal (opt-in)
│   ├── FindMouseService.swift       # Shared modifier tap: double=find mouse, triple=presentation pointer
│   ├── DefaultInputSourceService.swift # Force one input source after each app activation (opt-in)
│   ├── PresentationPointerService.swift # Click-through persistent cursor halo
│   ├── WindowSnappingService.swift  # Native-first snap engine; own placement as fallback
│   ├── WindowSnapGeometry.swift     # Pure placement math + Accessibility ↔ Cocoa flip
│   ├── WindowGestureTargeting.swift # Point → window/zone resolution + control guard
│   ├── NativeWindowTilingService.swift # Presses macOS' own Window-menu tiling items
│   ├── SystemWindowTilingSetting.swift # Reads/writes macOS' own drag-to-edge tiling
│   ├── WindowSnapPreviewService.swift # Snap-zone preview overlay
│   ├── WindowSnapHotKeyService.swift # Global snap hotkeys (opt-in)
│   ├── TitlebarGestureService.swift # Titlebar swipe-to-snap (CGEventTap, opt-in)
│   ├── AccessibilityPermission.swift # Shared AXIsProcessTrusted check + prompt
│   ├── LaunchAtLoginService.swift   # SMAppService login-item registration
│   ├── KeepAwakeService.swift       # IOPMAssertion + AC clamshell virtual display (opt-in, default off)
│   ├── PageRateService.swift        # vm_statistics64 swap page rate (nonisolated)
│   ├── SMCInfo.swift                # SMC temperature + fan
│   ├── CLIBinaryResolver.swift      # which/path for AI CLIs
│   ├── FinderMenuHostService.swift  # Host-side FinderSync IPC + dispatch
│   ├── FinderMenuFileService.swift  # New file, templates, copy/move
│   ├── FinderMenuSystemService.swift # Hide items, reveal hidden files
│   ├── FinderMenuTerminalService.swift # Open in terminal / configured app
│   ├── DisplayControl/              # Opt-in DDC hardware brightness (Apple Silicon)
│   └── AIUsage/                     # Shared AI-usage fetch helpers
│       ├── PTYProbe.swift           # Reusable PTY capture engine (Claude/Codex CLI scrape)
│       ├── KeychainCredentialReader.swift # `security` CLI Keychain read (no auth dialog)
│       └── UsageWarmupService.swift # Headless CLI send to keep the usage window warm
├── ViewModels/                      # @Observable / ObservableObject; @MainActor for UI
│   ├── SystemMonitor.swift          # Timer → collect → publish SystemSnapshot
│   ├── SettingsManager.swift        # UserDefaults-backed preferences
│   ├── AIUsageMonitor.swift         # Claude/Codex/Gemini polling coordinator
│   ├── UsageWarmupManager.swift     # Opt-in fixed-interval keep-alive ping for Claude/Codex
│   ├── AppMemoryManager.swift       # Process list + cleanup state
│   ├── LocalizationManager.swift    # Language change broadcast
│   ├── SystemAppFilter.swift        # Apple-signed app exclusion list
│   ├── CleaningModeViewModel.swift  # 60s countdown + keyboard lock
│   ├── FindMouseCoordinator.swift   # Settings → FindMouseService wiring (opt-in)
│   ├── DefaultInputSourceCoordinator.swift # Settings → DefaultInputSourceService wiring (opt-in)
│   ├── SystemWindowTilingSettings.swift # Observable facade over macOS' tiling switches
│   ├── FinderMenuConfigStore.swift  # Finder menu prefs in the app group
│   ├── DisplayControlManager.swift  # Opt-in brightness lifecycle
│   ├── PerformanceRecordingManager.swift # 48h product-resource session
│   ├── LicenseManager.swift         # License state: validate stored code, activate/deactivate
│   └── UpdateManager.swift          # Update UI state machine
├── Views/                           # SwiftUI panels/settings; AppKit for menu bar
│   ├── StatusBar/StatusBarView.swift
│   ├── Popover/
│   │   ├── PopoverContentView.swift       # Tab root
│   │   ├── OverviewTabView.swift
│   │   ├── CleanupTabView.swift
│   │   ├── DebugSnapshot.swift
│   │   └── Components/
│   │       ├── AppRowView.swift
│   │       ├── ChildProcessRowView.swift
│   │       ├── AIUsageCard.swift
│   │       ├── Sparkline.swift             # SwiftUI trend mini-chart
│   │       ├── SpinningFanIcon.swift       # CADisplayLink fan animation
│   │       ├── TabButton.swift
│   │       ├── VisualEffectView.swift      # NSViewRepresentable blur
│   │       └── ColorExtensions.swift
│   ├── Settings/SettingsView.swift
│   ├── Settings/FindMouseSettingsSection.swift
│   ├── Settings/WindowManagementSettingsSection.swift
│   ├── Settings/DefaultInputSourceSettingsSection.swift
│   ├── Settings/FinderMenuActionsSection.swift
│   ├── Settings/FinderMenuTemplatesSection.swift
│   ├── Settings/ActivationSection.swift
│   ├── Theme/                           # ThemeDefinition + Background Host/Router/Scenes
│   ├── Permission/PermissionAlertCenter.swift  # Themed AX permission panel (borderless)
│   ├── About/AboutView.swift
│   ├── CleaningMode/
│   │   ├── CleaningModeOverlayController.swift
│   │   └── CleaningModeOverlayView.swift
│   ├── Toast/ToastCenter.swift            # Transient toast notifications
│   └── Update/UpdateWindowView.swift
├── Utilities/
│   ├── AXElementReader.swift        # Stateless reads over an AXUIElement
│   ├── ByteFormatter.swift          # Stateless byte/rate formatting
│   ├── MetricHistory.swift          # Ring buffer of recent samples (sparklines)
│   ├── SVGIcon.swift                # Template-tinted bundle SVG
│   └── WindowSnapIconProvider.swift # SF Symbol icons for snap actions
└── Resources/
    ├── Icons/                       # Metric SVG outlines
    ├── FinderBlank.docx/.xlsx/.pptx # Minimal OOXML blanks (script/generate_finder_templates.py)
    ├── en.lproj/Localizable.strings
    ├── zh-Hans.lproj/Localizable.strings
    ├── ja.lproj/Localizable.strings
    └── ko.lproj/Localizable.strings
```

Repo-root companions: `FinderMenu/` (shared models + IPC) and `FinderMenuExtension/` (FinderSync).

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

**Shape C — opt-in event-tap services.** `ScrollDirectionService`, `WindowSnapHotKeyService`,
`TitlebarGestureService`, `FindMouseService`, and `KeyboardLockService` each own a `CGEventTap`
(or an Accessibility session via `WindowSnappingService`) behind a `start()/stop()` lifecycle.
They are the only services that hold OS-level taps, so they are also the only ones gated by
the "default off" rule: AppDelegate creates the tap **only** when the owning switch turns on
(`windowManagementEnabled` for the window trio; `scrollReverse*` for scrolling;
`findMouseEnabled` for Find My Mouse; cleaning-mode activation for the keyboard lock) and
calls `stop()` immediately when it turns off. `start()` returns `false` when Accessibility
permission is missing — the caller keeps the switch on and retries on `didBecomeActive`.
None of these run on a clean default install. See *Default form (zero-intrusion)* below.

`DefaultInputSourceService` is the same shape minus the tap: a `@MainActor` `start()/stop()`
service that owns an `NSWorkspace.didActivateApplicationNotification` observer instead of a
`CGEventTap`, gated by `defaultInputSourceEnabled` (default off). It does not need Accessibility
permission — `TISSelectInputSource` is unprivileged. Its only decision rule lives in the pure
`DefaultInputSourcePolicy`: **correct drift only inside a 1.2 s window after an app activation**, so a
deliberate `Ctrl+Space` outside that window (and any secure-input field) is left alone.

**Window management delegates to the system.** `WindowSnappingService` tries the native path
first: `NativeWindowTilingService` finds the tiling item macOS injects into the target app's
Window menu — matched by `AXIdentifier` (`_zoomLeft:`, `_zoomFill:`, …), never by localized
title — and presses it, so the frame, the animation, and the per-display visible-area rules are
the system's own. Only what macOS has no command for (thirds, display moves, minimize) is placed
by the engine through `WindowSnapGeometry`. Two measured facts shape this: the press reports
success even when the app is not frontmost and then does nothing at all, and the system animates
by really moving the window, so the outcome cannot be read back until ~600 ms later.
`confirmNativePlacement` waits that long and falls back to the engine's own placement if the
window never moved. Accessibility ↔ Cocoa conversion goes through `WindowSnapGeometry.flip`,
whose reference height must be the **primary** display's `maxY` — the topmost display shifts
every frame by its own height and breaks snapping on secondary displays only.

**Titlebar swipes are a heuristic, and the code says so.** A window's titlebar is not an
Accessibility concept — `AXTitlebar` and `AXTitleUIElement` are nil on AppKit and Electron
windows alike — so `WindowGestureTargeting` measures the band from where the system placed the
window's traffic lights and refuses a gesture that starts on a control the app itself reacts to
(`AXButton`, `AXTabGroup`, …; `AXScrollArea`/`AXGroup` are deliberately not controls, since
Electron reports its whole web content as those). Holding **Fn** switches the gesture to
`SnapGestureZone.pointer`, which skips both tests and acts on the window under the cursor — the
only way to reach apps that draw their own titlebar. Rationale, measurements, and the
alternatives that were rejected are in `docs/window-titlebar-gesture-research.md`.

**macOS' own drag-to-edge tiling is surfaced, not reimplemented.** `SystemWindowTilingSetting`
reads and writes `com.apple.WindowManager` so `WindowManagementDetail` can show the two system
switches; the first time window management is enabled the edge-drag switch is turned on once
(tracked by a non-preference flag), and the user's later choice is never overridden.

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

`ThemeDefinition` is the only product composition table: each `AppTheme` fixes its UI tokens,
`BackgroundSceneID`, and layout. `BackgroundHost` owns only sizing, clipping, window context,
and disabled hit testing; `BackgroundSceneRouter` creates the selected Scene with a structural
`@ViewBuilder` switch. System Glass, Sun Gold, Ink Night, and Data Paper own their
rendering independently. Dynamic Scenes expose typed code-side configurations for flow, motion,
grain, veil, and named light-field layers; Data Paper has its own static Canvas configuration
and does not consume those effects.
Shared tools are opt-in, not a common rendering pipeline.
`ThemeLayout` is injected separately from `UITokens` and is the only runtime layout truth.

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
| `load` | 8 | LoadAvg(1m) ÷ core count | ≤0.7→100, 0.7–1.0→linear 100→60, 1.0–2.0→linear 60→0 (weight deliberately low: macOS LoadAvg counts I/O-blocked threads, often inflated when idle) |
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

## Diagnostics vs Performance Recording

These are separate systems and must never share storage or exports:

- `DiagnosticLogService` is the always-on fault journal. Events are never discarded by severity.
  Continuous metrics are time-throttled; probe and capability records write on first observation,
  every state change, and a sparse heartbeat. Collector absence must include a stable `reasonCode`,
  source, stage/candidate evidence where applicable, and must not collapse silently into `nil`.
- `DiagnosticReportService` creates a user-initiated ZIP containing environment context, fresh
  hardware probes, relevant non-secret settings, and the bounded diagnostic journal. It excludes
  product performance recordings and never includes serial numbers, credentials, usernames, or raw
  home paths. Diagnostics retain 7 days with a 50 MB total cap.
- `PerformanceLogService` records only this app's CPU, memory, wakeup, disk, and companion system
  load metrics during the explicit 48-hour performance session. It writes under `Performance
  Recordings`, uses its own schema/lifecycle, retains 14 days, and is not a user-behavior log.

## Auto-Update

Zero-dependency self-updater. Checks the Cloudflare R2 channel marker (falling back to
GitHub Releases), downloads the DMG, verifies it cryptographically (R2 channel also checks
the SHA-256 sum), replaces the running app via a detached shell script after exit.

```
UpdateManager (@MainActor, ObservableObject)
 ├── phase: idle → checking → downloading(pct) → installing → idle
 └── UpdateService (actor)
      ├── check(): GET download.onecat.dev/latest-{stable,beta}.json → GitHub Releases fallback
      ├── download(): stream DMG to temp file; R2 channel verifies .sha256; report progress
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
- **No content plates.** Instrument chrome sits on the scene. Do not wrap sections, rows,
  or the popover body in a filled card / smoked glass / reading plate to fix contrast —
  any `AppTheme`, not just Neon. Contrast is ink vs the scene. Tab tracks, wells, and
  hover washes are not section cards. Neon `surfaceFill` stays `.clear`.
- **Content owns the visual hierarchy.** Health, live metrics, status, and trends must read
  before navigation chrome. Tab tracks, selected states, toolbar controls, wells, and hover
  washes must never become the panel's darkest, brightest, most saturated, or highest-contrast
  region. Express selection with restrained type weight, a light wash, or a fine indicator —
  never a dominant filled control that competes with instrument data.

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

Four languages: en, zh-Hans, ja, ko. zh-Hans is the source language; en/ja/ko are translations.

User-facing strings: `String(localized:)` or `NSLocalizedString`. Adding a key means
updating all four `Resources/<lang>.lproj/Localizable.strings`. Coverage check:
`./script/validate_localization.sh`. `LocalizationManager` broadcasts language changes so
views reload.

### Translation principles

- **Match the source's conciseness.** A short Chinese term stays a short term in every
  language. Never expand a term into a sentence or long phrase — e.g. 「右键菜单」is
  `Right-Click Menu` / `右クリックメニュー` / `우클릭 메뉴`, not "Finder Right-Click Menu".
- **No over-translation.** Don't add qualifiers or explanation the Chinese source doesn't
  carry (e.g. no "(Mouse Only)" suffix on a label). Clarification goes in a separate
  `*.hint` / description string, never inside the label itself.
- **Native-speaker phrasing in every language.** en, ja, ko, and zh-Hans must each read
  as if written by a native speaker — idiomatic and natural, never translationese. Follow
  each language's own convention (e.g. 「退出软件」→ "Quit Light Stats"), not a literal
  word-for-word gloss of the Chinese source.

## Build

```bash
# Debug — one-shot: pkill running instance → build → open.
# Run it when a change needs to be seen running: UI tweaks, anything needing visual
# verification, or after finishing a complete feature. Skip it for pure logic,
# refactors, copy/localization, or doc edits — those don't need a launch.
./script/debug-run.sh

# Debug — manual equivalent. Always pass -derivedDataPath; without it, opening
# build/DerivedData/… launches a stale previous build from ~/Library/Developer/Xcode/DerivedData.
xcodebuild -project "Light Stats.xcodeproj" -scheme "Light Stats" \
  -configuration Debug -derivedDataPath build/DerivedData build
open "build/DerivedData/Build/Products/Debug/Light Stats.app"

# Release DMG
./script/build.sh
```

Force-quit before relaunching: `pkill -9 -f "Light Stats"` (`./script/debug-run.sh` does this for you when you do need to launch).

**Version number is tag-driven; the pbxproj value is not.** Release version is the git tag:
`release.yml` parses `vX.Y.Z` → passes `VERSION` to `script/build.sh` → `MARKETING_VERSION=$VERSION` override →
the DMG and the About page show the tag version. The hardcoded `MARKETING_VERSION = 1.0.2` in
`project.pbxproj` is an **intentional local-Debug fallback only** (used by `script/debug-run.sh` / a plain
`xcodebuild`). It deliberately does not track tags and does not affect releases — leave it as-is, it is
not a stale-version bug.

### CI

| Workflow | Trigger | Action |
|----------|---------|--------|
| `quality.yml` | Reusable (`workflow_call`) | Parallel SwiftLint, localization, and XCTest gates |
| `build.yml` | Main push / PR / manual | Reuse quality gates, then package an unsigned DMG artifact |
| `deploy.yml` | Docs change on main / manual | Build and deploy GitHub Pages independently of app CI |
| `release.yml` | `v*` tags | Validate SemVer/main ancestry, reuse quality gates, sign + notarise + verify, publish GitHub Release, upload DMG to R2 |

Release ordering is mandatory: `prepare + quality` → `notarize` → `publish`. Release notes may run
in parallel with quality/notarization, but the final GitHub Release depends on both. Apple signing
secrets are scoped to the `notarize` job; `contents: write` is scoped to `publish` only.
R2 permalinks stay on separate channels and must not end in `.dmg`: `https://download.onecat.dev/stable`
(final) and `https://download.onecat.dev/beta` (prerelease). Each 302s to `Light-Stats-<version>.dmg`.
A permalink that itself ends in `.dmg` is saved without a version. In-app updates read the R2
channel marker first (`latest-stable.json` / `latest-beta.json`) and fall back to GitHub Releases.

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
- `FindMouseTriggerTests` — shared modifier sequence: double-tap delay/commit, triple-tap
  cancellation and toggle action, cooldown, reset, and key-code mapping. CGEventTap stays out of XCTest.
- `PresentationPointerServiceTests` — real 112×112 click-through overlay window lifecycle.
- `WindowSnapGeometryTests` — placement math for halves/quarters/thirds, the center shrink, the
  titlebar band measured from a window's traffic lights (32/34/46/52pt against a 44pt constant),
  Accessibility ↔ Cocoa flip (including that a wrong reference height shifts a frame by exactly
  the height of the display above the primary), display-to-display transfer clamping, and the
  snap-action → native command mapping.
- `WindowSnappingServiceTests` — drives the engine's own placement against a real window: halves,
  quarters and thirds land on the computed frame, maximize/restore round-trips, and placing twice
  is idempotent. Accessibility self-access needs no permission, so this runs in CI.
- `DefaultInputSourceTests` — the drift-correction window (inside = correct, outside = the
  user's `Ctrl+Space` wins, secure input = never), input-source dedup/sort, the unavailable-selection
  placeholder, a live TIS enumeration guard that non-selectable parent modes stay out of the
  picker, and a live switching test that posts `didActivateApplicationNotification` and asserts
  the input source actually moved. **The integration tests briefly change the system input source**
  (restored on exit) and skip unless both U.S. and WeType are enabled — CI runners have U.S. only.
- `FinderMenuTemplateTests` — built-in OOXML blanks stay in sync with `script/generate_finder_templates.py`,
  and custom templates store an independent file copy (name/format/contents), not UTF-8 text.
- `FinderMenuFileServiceTests` — new-file names, copy/move destinations, and template instantiation
  against a temporary directory (no live Finder).
- `LicenseValidatorTests` — offline activation codes: golden fixture pins the wire format
  against `script/license-tool`, plus round-trip, tamper/wrong-key/malformed rejection,
  input normalization, unknown-feature tolerance, payload-version guard.
- `LicenseManagerTests` — license state semantics: gift-period installs receive permanent Pro;
  after the paid-release switch, only new installs are locked, while prior gifts persist and invalid codes are rejected.
- `LightStatsSmokeTests` — model sentinels + formatter sanity.

## Default form (zero-intrusion)

The product is "monitoring core + extra tools that are off by default". Every capability
beyond read-only monitoring (window management, scroll reversal, Finder menu, default
input source, display brightness, AI usage, exit-node detection) ships **off**. A user
who never opts in must not see an entry point, be asked for a permission, or pay any
tap / collection / network cost.

Cold-start checklist — must hold on a clean install (empty `UserDefaults`):

- **No menu bar icon beyond monitoring.** The window-controls icon (`rectangle.split.2x1`)
  is created lazily and only when `windowManagementEnabled` is on. Default install shows
  only the monitoring status item.
- **No Accessibility prompt.** `AXIsProcessTrustedWithOptions` is never called by default;
  permission is requested only when the user actively enables a feature that needs it
  (scroll reversal, window management, Find My Mouse, cleaning mode).
- **No `CGEventTap`.** scroll / keyboard / window / find-mouse taps are all off by default;
  nothing is installed until the matching switch is turned on.
- **No input-source observer.** `defaultInputSourceEnabled` is off, so `DefaultInputSourceService`
  never registers for app activation and never calls `TISSelectInputSource` on a clean install.
- **No outbound request at all by default.** `autoCheckUpdates` is now opt-in (default off),
  alongside exit-node detection and AI usage polling. A clean install makes zero network calls.
- **No privileged helper.** The app bundle contains no privileged executable, LaunchDaemon,
  or `SMAppService` daemon.
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
- No content cards behind instrument readouts — the scene is the surface. Do not
  reintroduce Bento-style plates as “reading boards”.
- No plugin system — every metric is a built-in Service.
- No privileged helper or battery charge-control feature.
- Not an input method and not an input-source manager box — it only selects among input sources
  macOS already has, and only for one global default. No per-app rules, no website rules, no indicator.
- No remote telemetry — the app phones home only for user-initiated update checks and opt-in exit-node detection.
- No Intel support — `ARCHS = arm64`, so this ships Apple Silicon only, and the private-API display
  (DDC) code has no x86_64 fallback. Re-adding Intel is a documented multi-file operation, not a
  one-line revert: read `docs/intel-support.md` before touching it.
