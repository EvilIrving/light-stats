# Light Stats

[![Build](https://github.com/EvilIrving/light-stats/actions/workflows/build.yml/badge.svg)](https://github.com/EvilIrving/light-stats/actions/workflows/build.yml)
[![Release](https://github.com/EvilIrving/light-stats/actions/workflows/release.yml/badge.svg)](https://github.com/EvilIrving/light-stats/actions/workflows/release.yml)

Light Stats is a compact macOS menu bar monitor for CPU, GPU, memory, disk, disk I/O, network, proxy route, battery, temperature, fan, process, AI subscription usage, and overall system health.

**English** · [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

---

## Screenshots

| Overview | Cleanup |
|----------|---------|
| <img src="docs/screenshots/popover-overview.png" width="320" alt="Overview panel" /> | <img src="docs/screenshots/popover-cleanup.png" width="320" alt="Cleanup panel" /> |

---

## Overview

Light Stats keeps core system metrics visible in the menu bar and opens a detailed floating panel when you need more context. It is designed for users who want quick status checks without keeping Activity Monitor open, and for developers who want a native SwiftUI/AppKit reference for menu bar monitoring.

The app uses native macOS APIs for routine sampling and keeps network-based diagnostics opt-in.

---

## Features

### Menu Bar

- Compact two-line status items
- Fixed-width values to avoid layout jumping
- Optional items for Logo, CPU, GPU, MEM, Disk, Net, Fan, Battery, and Health
- Network upload and download speed display
- Optional health score display

### Overview Panel

- CPU, GPU, memory, and load average
- Battery status, charge level, cycle count, health, power, and temperature when available
- Disk usage and aggregate disk I/O speed
- Network speed, local proxy state, and optional public exit-node information
- Temperature, fan, and disk status strip
- Top CPU processes and P/E core usage charts
- System health score with dimension-level summary
- Claude Code and Codex subscription usage when AI monitoring is enabled

### Memory Cleanup

- Memory pressure overview
- Swap warning
- App list sorted by memory usage
- Normal quit and force quit with confirmation
- Expandable child process details

### Network and Proxy

Light Stats detects local proxy configuration from environment variables, system proxy settings, and active tunnel interfaces without sending external requests.

Public exit-node detection is optional. When enabled, it can query a selected geo-IP provider for public IP, location, ASN, and ISP, then cache the result to avoid repeated requests.

### AI Subscription Usage

When enabled, Light Stats reads Claude Code and Codex credentials stored locally by their respective CLIs and displays current subscription utilization (5-hour and 7-day windows) in the overview panel. AI monitoring is disabled by default and never transmits credentials to any service other than the provider's own usage endpoint.

### Health Score

The health score summarizes CPU, memory, load average, disk usage, temperature, battery, and disk I/O into a 0-100 score. Optional dimensions are reweighted automatically when a machine does not expose certain sensors.

---

## Privacy

Exit-node detection is disabled by default. Local proxy detection does not contact any external service.

When exit-node detection is enabled, the app sends a request to the selected geo-IP provider to identify the current public IP and network owner. The result is cached for 60 seconds and failures degrade silently.

---

## Settings

- Menu bar item visibility
- Refresh rate: Low (5s), Medium (2s), High (1s)
- Temperature unit: Celsius or Fahrenheit
- Network speed unit: Auto, KB/s, or MB/s
- Exit-node detection and provider selection
- AI monitoring toggle (Claude Code and Codex usage)
- Language: Simplified Chinese, English, Japanese, Korean, or system language

---

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full development guide.

### Requirements

- macOS 14+ (macOS 26 Liquid Glass visual style supported)
- Xcode 16 or newer recommended
- Swift 5.9+
- SwiftLint for local linting (`brew install swiftlint`)

### Build

```bash
# Debug build
xcodebuild -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" \
  -configuration Debug build

# Release DMG (with optional signing/notarization via env vars)
./build.sh
```

### Quality Checks

```bash
# Swift style and safety checks
swiftlint lint --strict

# Localization key coverage across en / zh-Hans / ja / ko
./validate_localization.sh
```

GitHub Actions runs SwiftLint, localization validation, release build, artifact upload, signing/notarization on tags, and GitHub Release creation.

### Tests

A starter XCTest suite lives in `LightStatsTests/LightStatsSmokeTests.swift`. Add it once in Xcode as a Unit Testing Bundle target named `LightStatsTests`, then run:

```bash
xcodebuild test \
  -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" \
  -destination 'platform=macOS'
```

### Tech Stack

- SwiftUI for panel and settings
- AppKit for menu bar integration and custom drawing
- Combine and Swift Concurrency
- Mach API, IOKit, CFNetwork, Network, SMC, and getifaddrs

### Architecture

The app separates metrics into models, services, view models, and views. `SystemMonitor` coordinates sampling and publishes snapshots to the UI, while service types collect data for each metric area.

Cached or asynchronous collectors, such as exit-node and battery smart-data readers, use actors. Lightweight local helpers stay synchronous where appropriate.

### Project Layout

- `Light Stats/Models/`: metric data structures
- `Light Stats/Services/`: system data collection and scoring
- `Light Stats/ViewModels/`: app state and sampling coordination
- `Light Stats/Views/StatusBar/`: menu bar rendering
- `Light Stats/Views/Popover/`: floating panel UI
- `Light Stats/Views/Settings/`: settings UI
- `Light Stats/Resources/`: localized strings
- `LightStatsTests/`: starter XCTest smoke tests
- `.github/workflows/`: build and release automation
- `.github/ISSUE_TEMPLATE/`: issue forms for bug reports and feature requests

---

## Roadmap

- External disk classification and system-volume filtering
- Full unit-setting coverage across every visible value
- More detailed network diagnostics
- Optional menu bar refinements for fan and health indicators
- Additional validation across Intel, Apple Silicon, laptop, and desktop Macs
