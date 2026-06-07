# Light Stats

Light Stats is a compact macOS menu bar monitor for CPU, GPU, memory, disk, disk I/O, network, proxy route, battery, temperature, fan, process, and overall system health.

> 中文版请查看 [README.zh.md](README.zh.md)

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

### Memory Cleanup

- Memory pressure overview
- Swap warning
- App list sorted by memory usage
- Normal quit and force quit with confirmation
- Expandable child process details

### Network and Proxy

Light Stats detects local proxy configuration from environment variables, system proxy settings, and active tunnel interfaces without sending external requests.

Public exit-node detection is optional. When enabled, it can query a selected geo-IP provider for public IP, location, ASN, and ISP, then cache the result to avoid repeated requests.

### Health Score

The health score summarizes CPU, memory, disk usage, temperature, and disk I/O into a 0-100 score. Optional dimensions are reweighted automatically when a machine does not expose certain sensors.

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
- Language: Simplified Chinese, English, Japanese, or system language

---

## Development

### Requirements

- macOS 14+
- Xcode 16 or newer recommended
- Swift 5.9+

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

---

## Roadmap

- External disk classification and system-volume filtering
- Full unit-setting coverage across every visible value
- More detailed network diagnostics
- Optional menu bar refinements for fan and health indicators
- Additional validation across Intel, Apple Silicon, laptop, and desktop Macs
