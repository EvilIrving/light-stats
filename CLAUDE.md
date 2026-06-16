# AGENTS.md — Light Stats

> **Keep `CLAUDE.md` and `AGENTS.md` identical.** They are mirror copies — any edit to one
> must be applied to the other in the same change so their contents never diverge.

## Project Overview

Light Stats is a native macOS menu bar system monitor. It shows CPU, GPU, memory, disk, disk I/O, network, proxy, battery, temperature, fan, process, and system health in a compact menu bar widget with a detailed floating panel.

Target: macOS 14+ · Swift 5.9+ · SwiftUI + AppKit · Xcode 16+

## Architecture

```
┌─ App Entry ──────────────────────────────────────────┐
│  LightStatsApp.swift     @main App, Settings scene    │
│  AppDelegate.swift       Menu bar status item + popover│
└──────────────────────────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
    ┌─ ViewModels ────┐ ┌─ Services ───┐ ┌─ Models ──┐
    │ SystemMonitor    │ │ PowerService │ │ CPUInfo   │
    │ SettingsManager  │ │ ProcessSvc   │ │ GPUInfo   │
    │ AIUsageMonitor   │ │ ExitNodeSvc  │ │ MemInfo   │
    │ AppMemoryManager │ │ DiskIOSvc    │ │ DiskInfo  │
    │ LocalizationMgr  │ │ HealthScore  │ │ NetInfo   │
    │ SystemAppFilter  │ │ ProxyDetector│ │ ProxyInfo │
    └──────────────────┘ │ ClaudeUsage  │ │ BatInfo   │
                          │ CodexUsage   │ │ HealthSc. │
                          │ SMCInfo      │ │ ProcStats │
                          └──────────────┘ │ AIUsageI. │
                                           │ CoreType  │
                                           │ AppGroup  │
                                           └───────────┘
                           │
                           ▼
    ┌─ Views ──────────────────────────────────────────┐
    │  StatusBar/   StatusBarView — menu bar rendering  │
    │  Popover/     PopoverContent, Overview, Cleanup   │
    │  Popover/Components/  BentoCard, AppRow, AIUsage  │
    │  Settings/    SettingsView                        │
    │  About/       AboutView                           │
    └──────────────────────────────────────────────────┘
```

### Layer Rules

1. **Models** — Pure data structs. No logic, no imports of Services/ViewModels.
2. **Services** — System data collection (Mach API, IOKit, SMC, CFNetwork). Cached/async collectors use actors. Lightweight local helpers stay synchronous.
3. **ViewModels** — `@Observable` classes (Swift 6). `SystemMonitor` coordinates sampling + publishes snapshots.
4. **Views** — SwiftUI for panel/settings. AppKit for menu bar + custom drawing.
5. **Utilities** — Stateless formatters (ByteFormatter).

Never: View → Service directly (go through ViewModel). Never: Service → View (Services don't know about UI).

## Conventions

### Naming

- Swift types: `PascalCase` (`SystemMonitor`, `CPUInfo`, `ProxyDetector`)
- Functions: verb-first `camelCase` (`fetchMetrics()`, `startSampling()`)
- Published properties: descriptive names (`currentCPU`, `memoryPressure`)
- Private helpers: `private func ...` (Swift access control, no `_` prefix)

### Swift Concurrency

- Cached/async collectors use `actor` (e.g., `ExitNodeService`)
- ViewModels use `@Observable` (Swift 6 macro)
- `@MainActor` for UI-bound ViewModels and Views
- No blocking waits or semaphores in async contexts
- Use `Task { }` for fire-and-forget, `Task.detached { }` when isolation matters

### Code Style

- No `print()` / `NSLog()` anywhere — use `os.Logger`. This includes `#Preview`
  blocks and sample/mock code (SwiftLint scans them too; leave an empty closure
  with a comment instead of a `print`).
- No force-unwrap (`!`) unless provably safe with comment
- Prefer `guard let` over `if let` for early exits
- One type per file (except tightly coupled private helpers)
- File structure: imports → type declaration → properties → init → methods → extensions

### Lint (CI gate)

CI runs `swiftlint lint --strict`, which **promotes every warning to a hard error** —
a single warning fails the Build workflow. Before pushing, run `swiftlint lint --strict`
locally (`brew install swiftlint`) and fix all output.

**After every code change, run:**
```bash
swiftlint lint --strict && swiftlint --fix --strict && swiftlint lint --strict
```
This lints, auto-fixes what it can (trailing whitespace, etc.), then re-lints to confirm.

#### All thresholds (`.swiftlint.yml`)

| Rule | Threshold | Notes |
|------|-----------|-------|
| `line_length` | ≤140 chars | Comments, URLs exempt |
| `function_body_length` | ≤80 lines | |
| `file_length` | ≤500 lines | |
| `type_body_length` | ≤400 lines | enum/class/struct/actor body |
| `cyclomatic_complexity` | ≤12 | |
| `nesting` | ≤2 levels | Type nesting depth |
| `function_parameter_count` | ≤5 | |
| `identifier_name` | ≥2 chars | `id`/`x`/`y`/`i`/`w`/`h` etc. excluded |
| `large_tuple` | ≤2 members | |
| `force_cast` | warning | |
| `force_try` | warning | |
| `for_where` | prefer `where` | Don't nest `if` inside `for` |
| `shorthand_operator` | prefer `+=` over `x = x + 1` | |
| `implicit_optional_initialization` | no `= nil` | `var x: Type?` not `var x: Type? = nil` |
| `non_optional_string_data_conversion` | `Data(s.utf8)` not `Data?(s.data(using: .utf8))` | |
| `multiple_closures_with_trailing_closure` | no trailing closure if >1 closures | |
| `trailing_whitespace` | no trailing spaces | `swiftlint --fix` cleans this |
| `vertical_whitespace` | max 1 empty line | |
| `no_print` | **禁止** `print()` | warning; use `os.Logger` |
| `no_nslog` | **禁止** `NSLog()` | **error**; use `os.Logger` |

#### Daily coding checklist

Every time you write or edit code, check these **before** declaring done:

1. **No `print()` / `NSLog()`** — use `import OSLog` + `let log = Logger(...)`
2. **Line ≤ 140 chars** — wrap long chains / string literals
3. **Function ≤ 80 lines** — extract helpers if approaching
4. **File ≤ 500 lines** — extract new types/files if approaching
5. **No force-unwrap (`!`)** unless trivially provable + commented
6. **No `var x: Type? = nil`** — write `var x: Type?`
7. **`for x in xs where cond {}`** — not `for x in xs { if cond {} }`
8. **`x += 1`** — not `x = x + 1`
9. **No `let _ =`** — use `!= nil`
10. Run `swiftlint lint --strict` locally

`swiftlint --fix` auto-resolves trivial violations (trailing whitespace, redundant optional
init, etc.), but line-length, complexity, and the custom rules must be fixed by hand.

### Localization

Three languages: en, zh-Hans, ja. User-facing strings must use `NSLocalizedString` or `String(localized:)`. When adding a new key, update all three `.lproj/Localizable.strings` files.

## Health Score

`HealthScoreService` (pure, `nonisolated`) computes a 0–100 score from real-time **pressure**
signals — "is the Mac sluggish right now", not slow-moving capacity numbers. Philosophy: a
smooth machine stays high even with lots of RAM used / many apps open; the score only drops
when the system is *actually* struggling. Disk **usage %** was deliberately removed (it's a
capacity alert, not a responsiveness signal).

### Dimensions & weights

| Dimension | Weight | Signal | Score curve (100 = healthy) |
|-----------|-------:|--------|------------------------------|
| `cpu`         | 25 | CPU usage % | ≤50 →100, 50–85 →100..60, 85+ →60..0 |
| `memory`      | 30 | **pressure level + swap ratio** (min of the two) | level normal/warning/critical = 100/55/15; swap%RAM ≤2 →100, 2–10 →100..60, 10–25 →60..0 |
| `load`        | 15 | LoadAvg(1m) ÷ core count | per-core ≤0.7 →100, 0.7–1.0 →100..60, 1.0–2.0 →60..0 |
| `temperature` | 20 | **min(SMC temp, thermal state)** | temp ≤60 →100, 60–85 →100..60, 85+ →60..0; thermal nominal/fair/serious/critical = 100/80/45/10 |
| `gpu`         | 15 | GPU utilization % | ≤70 →100, 70–90 →100..60, 90+ →60..0 |
| `battery` / `diskIO` | 10 | **power slot** (hardware-chosen) | laptop: battery charge (on AC = 100; discharge ≥40 →100, <20 →0). desktop (no battery) falls back to disk I/O MB/s: ≤50 →100, 150 →60, 300 →0 |

Weights are **relative**: absent dimensions (sensor missing, or toggled off) drop out and the
remaining weights renormalize (`totalWeight`). All-off → returns `.perfect` (100).

### Key algorithm details

- **Bottleneck cap** (the important one): a single saturated *performance* dimension gets
  diluted by the weighted average, yet the user just feels "lag". So the final score is capped:
  `total ≤ worstPerformanceScore + bottleneckHeadroom (25)`. Performance dimensions =
  `{cpu, memory, load, temperature, gpu}`. The power slot (battery/diskIO) is **not** a lag
  source and does **not** participate in the cap.
- **Thermal throttling** is folded into the `temperature` dimension via `ProcessInfo.thermalState`
  (always readable, so the temp dimension is always present) — throttling is the most direct
  cause of visible slowdown.
- **Memory uses pressure, not usage %**: Apple Silicon compresses inactive pages, so even ~30 GB
  allocated on a 32 GB Mac can stay at "normal" pressure with zero swap. Usage % would false-alarm;
  pressure + swap is the honest signal.
- **Smoothing**: `smooth()` applies EMA with `smoothingAlpha = 0.35` (new sample 35%) so the
  number doesn't jolt between samples.
- **Grades**: 90–100 excellent · 75–89 good · 60–74 fair · 40–59 poor · <40 critical.

### Configurable dimensions

Which dimensions count is user-configurable in **Settings → Health Score Dimensions**:
`SettingsManager` exposes `healthInclude{CPU,Memory,Load,Temperature,GPU,Power}` toggles
(all default ON), assembled into `HealthScoreService.DimensionToggles` via
`healthDimensionToggles` and passed through `SystemMonitor.collect(... healthToggles:)` into
`compute(... toggles:)`. `Power` covers the battery/diskIO slot. Disabling a dimension removes
it and renormalizes the rest.

## Build

```bash
# Debug build — ALWAYS pass -derivedDataPath build/DerivedData, then launch THAT product.
xcodebuild -project "Light Stats.xcodeproj" -scheme "Light Stats" -configuration Debug \
  -derivedDataPath build/DerivedData build
open "build/DerivedData/Build/Products/Debug/Light Stats.app"

# Release + DMG (with optional signing/notarization)
./build.sh
```

> ⚠️ Without `-derivedDataPath`, `xcodebuild` writes to `~/Library/Developer/Xcode/DerivedData`,
> while `build/DerivedData/.../Debug/Light Stats.app` keeps a STALE build. `open`-ing that path
> then launches old code — you'll think your changes had no effect. Always build and launch from
> the same `build/DerivedData` path. After editing, force-quit first: `pkill -9 -f "Light Stats"`.

CI: `.github/workflows/build.yml` runs on every push/PR. Release workflow signs, notarizes, and creates a GitHub Release on `v*` tags.

## Key Files

| File | Role |
|------|------|
| `LightStatsApp.swift` | `@main` entry, Settings scene |
| `AppDelegate.swift` | Menu bar status item + popover lifecycle |
| `SystemMonitor.swift` | Central sampling coordinator, publishes snapshots |
| `SettingsManager.swift` | UserDefaults-backed preferences |
| `build.sh` | CI-compatible build/sign/package/notarize script |
| `Info.plist` | App metadata & LSUIElement |
| `LightStats.entitlements` | Hardened Runtime entitlements |

## Dependencies

None. Pure Apple frameworks only: SwiftUI, AppKit, Combine, Mach, IOKit, CFNetwork, Network, SMC (IOKit bridge).
