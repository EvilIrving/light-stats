# Light Stats

A macOS menu bar app that monitors CPU, GPU, memory, disk, and network usage. Click any item to see details in a popover. Includes memory cleanup.

> 中文版请查看 [README.zh.md](README.zh.md)

---

## What it does

Light Stats lives in your menu bar, showing real-time system metrics. No extra windows cluttering your screen.

**Design choices:**

- Info stays visible in the menu bar
- Fixed widths prevent the UI from jumping as numbers change
- Focus on monitoring first, cleanup second
- Protocols and dependency injection for testability

---

## Features

### Status Bar

Two-line layout in the menu bar:

- Top row: values (`62%`, `99 GB`) in 11pt monospace
- Bottom row: labels (`CPU`, `DISK`) in 8pt, lighter color
- Network: upload ↑ on top, download ↓ below, 10pt monospace

Fixed widths keep things stable (CPU: 26pt, Disk: 46pt). Toggle each item on/off in Settings (Logo, CPU, GPU, MEM, Disk, Net, Fan).

### Popover

Click a menu bar item to open a popover with two tabs:

**Overview:** Ring progress bars for CPU, GPU, and memory. Core usage list with color gradients. Network speed, disk info, and fan status.

**Memory:** Memory pressure overview. App list sorted by usage (descending). Close apps normally or force quit (with confirmation).

### Settings

- Toggle which items show in the menu bar
- Refresh rate: Low (5s), Medium (2s), High (1s)
- Units: Temperature (℃/℉), Network speed (Auto/KB/s/MB/s)
- Language: 简体中文, English, 日本語, or follow system

---

## Tech Stack

- Swift 5.9+
- SwiftUI for popover and settings, AppKit for menu bar and custom drawing
- Combine + Swift Concurrency
- macOS 14+
- Mach API, IOKit, SMC, getifaddrs for system metrics

### Architecture

Each metric has its own reader and manager class. Protocols like `ProcessService` and `SettingsManaging` decouple implementations. Dependency injection via constructors or properties makes testing easier. Global constants live in `AppConfig`.

---

## Implementation Status (Updated: 2026-01-16)

### Status Bar

| Feature | Status |
|---------|--------|
| NSStatusItem framework | ✅ Done |
| Two-line layout | ✅ Done |
| Fixed widths | ✅ Done |
| Item toggles | ✅ Done |
| Minimum display validation | ✅ Done |
| Fan animation | ❌ Not implemented |

### Popover

| Feature | Status |
|---------|--------|
| Two tabs | ✅ Done |
| Ring progress bars | ✅ Done |
| Core usage list | ✅ Done |
| Process sorting | ✅ Done |
| Force quit | ✅ Done |
| Auto-close | ❌ Not implemented |

### Global Features

| Feature | Status |
|---------|--------|
| Multi-language | ✅ Done |
| Dependency injection | ✅ Done |
| Global config | ✅ Done |
| Temperature units | ✅ Done |

---

## File Structure

- `Models/`: Data structures (CPUInfo, DiskInfo, etc.)
- `Services/`: System data collection (ProcessService, SMCInfo)
- `ViewModels/`: Business logic and state (SystemMonitor, AppMemoryManager, SettingsManager)
- `Views/`:
  - `StatusBar/`: Menu bar rendering
  - `Popover/`: Popover components and tabs
  - `Settings/`: Settings UI
- `Resources/`: Localization files (`Localizable.strings`)
- `Utilities/`: Formatters and helpers

---

## What's Next

Light Stats started as a prototype and grew into a full system monitor. The basics work: protocols, DI, multi-language support.

Still on the list:

- Fan animation
- Auto-close logic for the popover
- More metrics
