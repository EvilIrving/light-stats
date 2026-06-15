# Contributing to Light Stats

Thanks for contributing!

## Prerequisites

| Dependency | Version | Check |
|-----------|---------|-------|
| macOS | 14+ | System Settings → About |
| Xcode | 16+ | `xcodebuild -version` |
| Swift | 5.9+ | `swift --version` |

## Getting Started

```bash
git clone git@github.com:EvilIrving/light-stats.git
cd swift-menu-stats
open "Light Stats.xcodeproj"
```

Select the **Light Stats** scheme, pick **My Mac** as destination, and press ⌘R.

## Development

### Build

```bash
# Debug build (CLI)
xcodebuild -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" \
  -configuration Debug build

# Release + DMG (with optional signing)
./build.sh
```

### Lint

```bash
# Install SwiftLint
brew install swiftlint

# Run
swiftlint lint --strict

# Auto-fix
swiftlint --fix
```

### Run

The app runs as a menu bar agent (`LSUIElement = YES`). After building, open `build/output/Light Stats.app` or run from Xcode.

## Architecture

```
Models/        Pure data structs — no logic, no service imports
Services/      System data collection — Mach, IOKit, SMC, CFNetwork
ViewModels/    @Observable classes — coordinates sampling, publishes state
Views/         SwiftUI (panel/settings) + AppKit (menu bar)
```

Key rule: Views → ViewModels → Services → Models. Never skip a layer.

Full details in [`AGENTS.md`](AGENTS.md).

## Code Style

- No `print()` or `NSLog()` — use `os.Logger`
- No force-unwrap without a safety comment
- `guard let` over `if let` for early exits
- `@Observable` (Swift 6) not `@Published` / `ObservableObject`
- One type per file
- User-facing strings: `String(localized:)` with entries in all three `.lproj`

## Localization

Light Stats supports English, Simplified Chinese, and Japanese.

When adding a new string:
1. Add `String(localized: "key")` in your Swift code
2. Add the key to `Resources/en.lproj/Localizable.strings`
3. Add translations to `Resources/zh-Hans.lproj/Localizable.strings`
4. Add translations to `Resources/ja.lproj/Localizable.strings`

## Pull Request Process

1. Fork and create a feature branch
2. Run `swiftlint lint --strict` before pushing
3. Build and test on your Mac
4. Open a PR against `main` with a clear description
5. CI will run the build automatically

## Project Layout

```
Light Stats/
├── LightStatsApp.swift          # @main entry
├── AppDelegate.swift            # Menu bar + popover
├── Models/                      # Data types (CPUInfo, MemoryInfo, ...)
├── Services/                    # System data collection
├── ViewModels/                  # State management + sampling
├── Views/
│   ├── StatusBar/               # Menu bar rendering
│   ├── Popover/                 # Floating panel
│   │   └── Components/          # Reusable cards, rows
│   ├── Settings/                # Preferences UI
│   └── About/                   # About window
├── Utilities/                   # Formatters
└── Resources/                   # Localizable.strings (en/zh-Hans/ja)
```

## Questions?

Open a [Discussion](https://github.com/EvilIrving/light-stats/discussions) or an issue.
