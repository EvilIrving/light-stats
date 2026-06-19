# Contributing to Light Stats

## Prerequisites

| Dependency | Version | Check |
|-----------|---------|-------|
| macOS | 14+ | System Settings → About |
| Xcode | 16+ | `xcodebuild -version` |
| Swift | 5.9+ | `swift --version` |
| SwiftLint | latest | `brew install swiftlint` |

## Getting Started

```bash
git clone git@github.com:EvilIrving/light-stats.git
cd light-stats
open "Light Stats.xcodeproj"
```

Select the **Light Stats** scheme, pick **My Mac** as destination, press ⌘R.

## Build

```bash
# Debug (CLI)
xcodebuild -project "Light Stats.xcodeproj" -scheme "Light Stats" \
  -configuration Debug -derivedDataPath build/DerivedData build
open "build/DerivedData/Build/Products/Debug/Light Stats.app"

# Release DMG
./build.sh
```

The app runs as a menu bar agent (`LSUIElement = YES`). After building, force-quit any running instance first: `pkill -9 -f "Light Stats"`.

## Before Submitting

### Daily checklist

Run through these before declaring a change done:

1. No `print()` / `NSLog()` — use `import OSLog` + `let log = Logger(...)`
2. Line ≤ 140 chars
3. Function ≤ 80 lines — extract helpers if approaching
4. File ≤ 500 lines — extract new types/files if approaching
5. No force-unwrap (`!`) unless trivially provable + commented
6. `var x: Type?` not `var x: Type? = nil`
7. `for x in xs where cond {}` not `for x in xs { if cond {} }`
8. `x += 1` not `x = x + 1`
9. No `let _ = someOptional` — use `!= nil`

### Lint

```bash
swiftlint lint --strict && swiftlint --fix --strict && swiftlint lint --strict
```

CI runs `swiftlint lint --strict` — every warning is a hard error.

### Localization

```bash
./validate_localization.sh
```

When adding a user-facing string:
1. Use `String(localized: "key")` in Swift code
2. Add the key to `Resources/en.lproj/Localizable.strings`
3. Add translations to `zh-Hans`, `ja`, and `ko` lproj files

### Tests

```bash
xcodebuild test -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" -destination 'platform=macOS'
```

## Architecture

```
Views → ViewModels → Services → Models
         Utilities ↗
```

- **Models:** Pure data structs. No logic, no imports of Services/ViewModels.
- **Services:** System data collection. Actors for cached/async; nonisolated classes for sync syscalls.
- **ViewModels:** `@Observable` (Swift 6) or `ObservableObject`. `@MainActor` for UI-bound ones.
- **Views:** SwiftUI (panels/settings) + AppKit (menu bar). Receive ViewModels via `@Environment` or `@ObservedObject`.

Full contract in [`AGENTS.md`](AGENTS.md).

## Pull Request Process

1. Fork and create a feature branch
2. Run the daily checklist + `swiftlint lint --strict`
3. Build and test on your Mac
4. Open a PR against `main` with a clear description
5. CI runs lint + build automatically
