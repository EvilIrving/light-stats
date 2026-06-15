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

- No `print()` / `NSLog()` in production — use `os.Logger`
- No force-unwrap (`!`) unless provably safe with comment
- Prefer `guard let` over `if let` for early exits
- One type per file (except tightly coupled private helpers)
- File structure: imports → type declaration → properties → init → methods → extensions

### Localization

Three languages: en, zh-Hans, ja. User-facing strings must use `NSLocalizedString` or `String(localized:)`. When adding a new key, update all three `.lproj/Localizable.strings` files.

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
